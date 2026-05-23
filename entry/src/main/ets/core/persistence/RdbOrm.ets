import relationalStore from '@ohos.data.relationalStore';
import { DatabaseManager } from './DatabaseManager';

/**
 * 列类型；映射到 SQLite 原生类型。
 */
export type ColumnType = 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB' | 'BOOLEAN';

export interface ColumnDef {
  type: ColumnType;
  primaryKey?: boolean;
  notNull?: boolean;
  unique?: boolean;
  defaultValue?: string | number | boolean | null;
  /** 持久化时把 boolean -> 0/1，读取时 0/1 -> boolean。 */
  booleanCompat?: boolean;
}

export interface IndexDef {
  name: string;
  columns: string[];
  unique?: boolean;
}

export interface EntitySchema<T> {
  table: string;
  /** schema 版本；每次结构变更必须递增。 */
  version: number;
  columns: Record<string, ColumnDef>;
  indices?: IndexDef[];
  /** 字段名（TS）↔ 列名（SQL）映射；默认 identity。 */
  fieldToColumn?: Partial<Record<keyof T & string, string>>;
}

export type WhereOp = '=' | '!=' | '>' | '>=' | '<' | '<=' | 'like' | 'in' | 'not in' | 'is null' | 'is not null';
export type SortOrder = 'asc' | 'desc';
export type Primitive = string | number | boolean | null;

interface WhereClause {
  column: string;
  op: WhereOp;
  value?: Primitive | Primitive[];
  conjunction: 'AND' | 'OR';
}

/**
 * Migration 版本控制策略：
 *   1. 每个 entity 自带 version；ORM 把所有 entity 的最大版本号汇总成 RDB 全局 version。
 *   2. RDB 启动时若 store.version < target，遍历 registered entities 跑 createIfNotExists +
 *      调用 user-supplied migrators 升级；最后写入 target。
 *   3. 不允许降级；降级需要新建 db。
 */
export interface Migrator {
  fromVersion: number;  // 严格大于此版本号才会跑
  toVersion: number;    // 升至该版本号
  run: (rdb: relationalStore.RdbStore) => Promise<void>;
}

interface RegisteredEntity<T> {
  schema: EntitySchema<T>;
  migrators: Migrator[];
}

/**
 * ORM 风格 RDB 封装。
 * - defineEntity: 注册 entity（schema + migrators）
 * - QueryBuilder: chainable where/orderBy/limit/all/first/count
 * - CRUD: insert / update / upsert / delete / findOne / findMany / count
 * - Transaction: runInTransaction(async db => { ... })
 *
 * 用法：
 *   const VocabEntity = RdbOrm.defineEntity<VocabNote>({ table: 'vocab_notes', version: 1, columns: {...} });
 *   await RdbOrm.applyMigrations();
 *   await RdbOrm.insert(VocabEntity, vocab);
 *   const list = await RdbOrm.query(VocabEntity).where('userId', '=', uid).all();
 */
export class RdbOrm {
  private static entities: Map<string, RegisteredEntity<unknown>> = new Map<string, RegisteredEntity<unknown>>();

  // ---------- entity registration ----------

  static defineEntity<T>(schema: EntitySchema<T>, migrators: Migrator[] = []): EntitySchema<T> {
    RdbOrm.entities.set(schema.table, { schema: schema as EntitySchema<unknown>, migrators });
    return schema;
  }

  /** 启动时调用：自动建表 / 升级 / 建索引。 */
  static async applyMigrations(): Promise<void> {
    const rdb = DatabaseManager.get();
    const target = RdbOrm.computeTargetVersion();
    const current = rdb.version || 0;

    // 1. 建表（IF NOT EXISTS，幂等）
    RdbOrm.entities.forEach((reg) => {
      const sql = RdbOrm.buildCreateTableSql(reg.schema);
      rdb.executeSql(sql);
    });

    // 2. 跑 migrators（仅升级路径）
    if (current < target) {
      RdbOrm.entities.forEach((reg) => {
        const eligible = reg.migrators
          .filter((m) => m.fromVersion >= current && m.toVersion <= target)
          .sort((a, b) => a.toVersion - b.toVersion);
        eligible.forEach((m) => { m.run(rdb); });
      });
    }

    // 3. 建索引
    RdbOrm.entities.forEach((reg) => {
      const indices = reg.schema.indices ?? [];
      indices.forEach((idx) => {
        const unique = idx.unique ? 'UNIQUE' : '';
        const cols = idx.columns.join(', ');
        rdb.executeSql(`CREATE ${unique} INDEX IF NOT EXISTS ${idx.name} ON ${reg.schema.table} (${cols})`);
      });
    });

    rdb.version = target;
  }

  // ---------- CRUD ----------

  static async insert<T>(entity: EntitySchema<T>, value: T): Promise<number> {
    const rdb = DatabaseManager.get();
    const bucket = RdbOrm.toBucket(entity, value);
    return await rdb.insert(entity.table, bucket);
  }

  static async upsert<T>(entity: EntitySchema<T>, value: T): Promise<number> {
    const rdb = DatabaseManager.get();
    const bucket = RdbOrm.toBucket(entity, value);
    return await rdb.insert(
      entity.table,
      bucket,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE,
    );
  }

  static async update<T>(
    entity: EntitySchema<T>,
    patch: Partial<T>,
    where: (q: QueryBuilder<T>) => QueryBuilder<T>,
  ): Promise<number> {
    const rdb = DatabaseManager.get();
    const bucket = RdbOrm.toBucket(entity, patch as T);
    const builder = where(new QueryBuilder<T>(entity));
    return await rdb.update(bucket, builder.toPredicates());
  }

  static async delete<T>(
    entity: EntitySchema<T>,
    where: (q: QueryBuilder<T>) => QueryBuilder<T>,
  ): Promise<number> {
    const rdb = DatabaseManager.get();
    const builder = where(new QueryBuilder<T>(entity));
    return await rdb.delete(builder.toPredicates());
  }

  static async findOne<T>(
    entity: EntitySchema<T>,
    where: (q: QueryBuilder<T>) => QueryBuilder<T>,
  ): Promise<T | null> {
    const rows = await where(new QueryBuilder<T>(entity)).limit(1).all();
    return rows.length > 0 ? rows[0] : null;
  }

  static findMany<T>(entity: EntitySchema<T>): QueryBuilder<T> {
    return new QueryBuilder<T>(entity);
  }

  static query<T>(entity: EntitySchema<T>): QueryBuilder<T> {
    return new QueryBuilder<T>(entity);
  }

  static async count<T>(
    entity: EntitySchema<T>,
    where?: (q: QueryBuilder<T>) => QueryBuilder<T>,
  ): Promise<number> {
    const builder = where ? where(new QueryBuilder<T>(entity)) : new QueryBuilder<T>(entity);
    return await builder.count();
  }

  // ---------- transaction ----------

  /**
   * 简单事务支持。失败自动 rollback。
   * 注意：HarmonyOS RdbStore 的 begin/commit/rollback 是同步 API。
   */
  static async runInTransaction<R>(work: () => Promise<R>): Promise<R> {
    const rdb = DatabaseManager.get();
    rdb.beginTransaction();
    try {
      const result = await work();
      rdb.commit();
      return result;
    } catch (e) {
      rdb.rollBack();
      throw e as Error;
    }
  }

  // ---------- internal helpers ----------

  static toBucket<T>(entity: EntitySchema<T>, value: T): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    const cols = entity.columns;
    const keys = Object.keys(value as object);
    const map = entity.fieldToColumn ?? {};
    for (let i = 0; i < keys.length; i++) {
      const field = keys[i];
      const col = (map as Record<string, string>)[field] ?? field;
      const def = cols[col];
      if (!def) continue;
      let v: unknown = (value as Record<string, unknown>)[field];
      if (v === undefined) continue;
      if (def.booleanCompat && typeof v === 'boolean') v = v ? 1 : 0;
      bucket[col] = v as relationalStore.ValueType;
    }
    return bucket;
  }

  static fromCursor<T>(entity: EntitySchema<T>, cursor: relationalStore.ResultSet): T {
    const obj: Record<string, unknown> = {};
    const map = entity.fieldToColumn ?? {};
    const reverseMap: Record<string, string> = {};
    Object.keys(map).forEach((k) => { reverseMap[(map as Record<string, string>)[k]] = k; });
    const cols = entity.columns;
    Object.keys(cols).forEach((col) => {
      const idx = cursor.getColumnIndex(col);
      if (idx < 0) return;
      const def = cols[col];
      let v: unknown;
      switch (def.type) {
        case 'INTEGER': v = cursor.getLong(idx); break;
        case 'REAL': v = cursor.getDouble(idx); break;
        case 'BLOB': v = cursor.getBlob(idx); break;
        case 'BOOLEAN': v = cursor.getLong(idx) !== 0; break;
        case 'TEXT':
        default: v = cursor.getString(idx); break;
      }
      if (def.booleanCompat && typeof v === 'number') v = v !== 0;
      const field = reverseMap[col] ?? col;
      obj[field] = v;
    });
    return obj as T;
  }

  private static computeTargetVersion(): number {
    let max = 1;
    RdbOrm.entities.forEach((reg) => {
      if (reg.schema.version > max) max = reg.schema.version;
    });
    return max;
  }

  private static buildCreateTableSql<T>(schema: EntitySchema<T>): string {
    const parts: string[] = [];
    const cols = schema.columns;
    Object.keys(cols).forEach((name) => {
      const def = cols[name];
      const sqlType = def.type === 'BOOLEAN' ? 'INTEGER' : def.type;
      let line = `${name} ${sqlType}`;
      if (def.primaryKey) line += ' PRIMARY KEY';
      if (def.notNull) line += ' NOT NULL';
      if (def.unique) line += ' UNIQUE';
      if (def.defaultValue !== undefined && def.defaultValue !== null) {
        const lit = typeof def.defaultValue === 'string'
          ? `'${def.defaultValue}'`
          : String(def.defaultValue);
        line += ` DEFAULT ${lit}`;
      }
      parts.push(line);
    });
    return `CREATE TABLE IF NOT EXISTS ${schema.table} (${parts.join(', ')})`;
  }
}

/**
 * Builder 模式 query API。
 * 支持链式 where / andWhere / orWhere / orderBy / limit / offset。
 * Type-safe via generic T。
 */
export class QueryBuilder<T> {
  private clauses: WhereClause[] = [];
  private orders: { column: string; order: SortOrder }[] = [];
  private limitN: number | null = null;
  private offsetN: number | null = null;

  constructor(private readonly entity: EntitySchema<T>) {}

  where(field: keyof T & string, op: WhereOp, value?: Primitive | Primitive[]): QueryBuilder<T> {
    return this.pushClause('AND', field, op, value);
  }

  andWhere(field: keyof T & string, op: WhereOp, value?: Primitive | Primitive[]): QueryBuilder<T> {
    return this.pushClause('AND', field, op, value);
  }

  orWhere(field: keyof T & string, op: WhereOp, value?: Primitive | Primitive[]): QueryBuilder<T> {
    return this.pushClause('OR', field, op, value);
  }

  orderBy(field: keyof T & string, order: SortOrder = 'asc'): QueryBuilder<T> {
    this.orders.push({ column: this.colOf(field), order });
    return this;
  }

  limit(n: number): QueryBuilder<T> { this.limitN = n; return this; }

  offset(n: number): QueryBuilder<T> { this.offsetN = n; return this; }

  async all(): Promise<T[]> {
    const rdb = DatabaseManager.get();
    const cursor = await rdb.query(this.toPredicates(), Object.keys(this.entity.columns));
    const out: T[] = [];
    while (cursor.goToNextRow()) {
      out.push(RdbOrm.fromCursor(this.entity, cursor));
    }
    cursor.close();
    return out;
  }

  async first(): Promise<T | null> {
    this.limitN = 1;
    const rows = await this.all();
    return rows.length > 0 ? rows[0] : null;
  }

  async count(): Promise<number> {
    const rdb = DatabaseManager.get();
    const cursor = await rdb.query(this.toPredicates(), ['COUNT(*) AS cnt']);
    let n = 0;
    if (cursor.goToFirstRow()) {
      n = cursor.getLong(cursor.getColumnIndex('cnt'));
    }
    cursor.close();
    return n;
  }

  /** 转换为 RdbPredicates；公开供 RdbOrm.update/delete 使用。 */
  toPredicates(): relationalStore.RdbPredicates {
    const p = new relationalStore.RdbPredicates(this.entity.table);
    let firstClause = true;
    for (let i = 0; i < this.clauses.length; i++) {
      const c = this.clauses[i];
      if (!firstClause) {
        if (c.conjunction === 'OR') p.or(); else p.and();
      }
      firstClause = false;
      const v = c.value;
      switch (c.op) {
        case '=': p.equalTo(c.column, v as relationalStore.ValueType); break;
        case '!=': p.notEqualTo(c.column, v as relationalStore.ValueType); break;
        case '>': p.greaterThan(c.column, v as relationalStore.ValueType); break;
        case '>=': p.greaterThanOrEqualTo(c.column, v as relationalStore.ValueType); break;
        case '<': p.lessThan(c.column, v as relationalStore.ValueType); break;
        case '<=': p.lessThanOrEqualTo(c.column, v as relationalStore.ValueType); break;
        case 'like': p.like(c.column, v as string); break;
        case 'in': p.in(c.column, v as relationalStore.ValueType[]); break;
        case 'not in': p.notIn(c.column, v as relationalStore.ValueType[]); break;
        case 'is null': p.isNull(c.column); break;
        case 'is not null': p.isNotNull(c.column); break;
        default: break;
      }
    }
    for (let i = 0; i < this.orders.length; i++) {
      const o = this.orders[i];
      if (o.order === 'desc') p.orderByDesc(o.column); else p.orderByAsc(o.column);
    }
    if (this.limitN !== null) p.limitAs(this.limitN);
    if (this.offsetN !== null) p.offsetAs(this.offsetN);
    return p;
  }

  private pushClause(
    conjunction: 'AND' | 'OR',
    field: keyof T & string,
    op: WhereOp,
    value?: Primitive | Primitive[],
  ): QueryBuilder<T> {
    this.clauses.push({ column: this.colOf(field), op, value, conjunction });
    return this;
  }

  private colOf(field: keyof T & string): string {
    const map = this.entity.fieldToColumn ?? {};
    return (map as Record<string, string>)[field] ?? field;
  }
}
