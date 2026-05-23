/**
 * NotificationTemplates.ets — W13-C4 多端通知文案模板（中文）
 *
 * 所有用户可见的通知文案集中在这里，方便：
 *   - 统一审核 / 改文案 / 接 i18n
 *   - 多变体随机抽样，避免每天同一句话造成「通知盲区」
 *
 * 文案设计原则：
 *   - 标题 ≤ 20 字，正文 ≤ 60 字
 *   - 不强势营销，强调「你」、「我们」、对话式
 *   - 试用 / 续费类文案带明确 CTA
 *
 * 用法：
 *   const tmpl = NotificationTemplates.pickReadingReminder('morning');
 *   notificationManager.publish({ ..., title: tmpl.title, text: tmpl.body });
 */

export type ReadingTimeSlot = 'morning' | 'noon' | 'evening' | 'night' | 'random';

export interface NotificationContent {
  title: string;
  body: string;
}

/** 模板 + slot 元信息（slot 用于按时间段过滤合适的文案）。 */
interface ReadingTemplate extends NotificationContent {
  slots: ReadingTimeSlot[];
}

/** 阅读提醒：5 个变体（早 / 午 / 晚 / 睡前 / 通用）。 */
const READING_REMINDERS: ReadingTemplate[] = [
  {
    title: '早安，要不要读 10 分钟？',
    body: '今天的故事在等你。读 10 分钟，唤醒大脑。',
    slots: ['morning'],
  },
  {
    title: '午休时间，换一种节奏',
    body: '放下手头的活，让一段文字带你喘口气。',
    slots: ['noon'],
  },
  {
    title: '今晚一段安静的阅读',
    body: '继续昨晚的章节？只剩 ${remaining} 页就读完了。',
    slots: ['evening'],
  },
  {
    title: '睡前 10 分钟',
    body: '关灯之前，再读一段。明天会感谢现在的你。',
    slots: ['night'],
  },
  {
    title: '该看书了',
    body: '已经 ${days} 天没翻开它，要不要继续？',
    slots: ['random'],
  },
];

/** 复习提醒：3 个变体。 */
const REVIEW_REMINDERS: NotificationContent[] = [
  { title: '生词在等你复习',  body: '今天有 ${count} 个生词到了复习时间，5 分钟搞定。' },
  { title: '记得越快，忘得越慢', body: '${count} 个单词到了关键复习节点，错过就要重学。' },
  { title: '生词卡片提醒',     body: '维持节奏，今天的复习只要 ${minutes} 分钟。' },
];

/** 单点模板（不需要随机）。 */
const SUBSCRIPTION_RENEW: NotificationContent = {
  title: '订阅明天到期',
  body: '续订只要点一下，避免阅读中断。',
};

const TRIAL_EXPIRING: NotificationContent = {
  title: '试用还剩 ${days} 天',
  body: '体验完整的 AI 解词、跨端同步、TTS 朗读？现在升级有优惠。',
};

const HANDOFF_AVAILABLE: NotificationContent = {
  title: '在 ${device} 上继续阅读',
  body: '《${book}》读到了第 ${page} 页，跨端无缝接续。',
};

const NEW_BOOK_RELEASED: NotificationContent = {
  title: '新书上架：${book}',
  body: '${author} 的新作刚刚加入书架，要看看吗？',
};

/**
 * 模板渲染：把 ${var} 替换为实际值。
 * 没有提供的变量原样保留，避免渲染崩。
 */
function render(template: NotificationContent, vars: Record<string, string | number>): NotificationContent {
  const fill = (s: string): string => {
    return s.replace(/\$\{(\w+)\}/g, (_m, key: string) => {
      const v = vars[key];
      return v === undefined || v === null ? `\${${key}}` : String(v);
    });
  };
  return { title: fill(template.title), body: fill(template.body) };
}

/**
 * 根据当前小时推断时间段（与 ReadingTemplate.slots 对齐）。
 *   05:00–10:59 → morning
 *   11:00–13:59 → noon
 *   18:00–21:59 → evening
 *   22:00–04:59 → night
 *   其它       → random
 */
function inferSlot(date: Date = new Date()): ReadingTimeSlot {
  const h = date.getHours();
  if (h >= 5 && h < 11) return 'morning';
  if (h >= 11 && h < 14) return 'noon';
  if (h >= 18 && h < 22) return 'evening';
  if (h >= 22 || h < 5) return 'night';
  return 'random';
}

export class NotificationTemplates {
  /** 阅读提醒：根据时间段挑选变体；vars 支持 `remaining` / `days`。 */
  static pickReadingReminder(
    slot: ReadingTimeSlot = inferSlot(),
    vars: Record<string, string | number> = {},
  ): NotificationContent {
    const matched = READING_REMINDERS.filter((t) => t.slots.includes(slot));
    const pool = matched.length > 0 ? matched : READING_REMINDERS;
    const picked = pool[Math.floor(Math.random() * pool.length)];
    return render(picked, vars);
  }

  /** 复习提醒：随机挑一条，vars 支持 `count` / `minutes`。 */
  static pickReviewReminder(vars: Record<string, string | number> = {}): NotificationContent {
    const picked = REVIEW_REMINDERS[Math.floor(Math.random() * REVIEW_REMINDERS.length)];
    return render(picked, vars);
  }

  /** 续费提醒。 */
  static subscriptionRenew(): NotificationContent {
    return SUBSCRIPTION_RENEW;
  }

  /** 试用到期，vars 支持 `days`。 */
  static trialExpiring(days: number): NotificationContent {
    return render(TRIAL_EXPIRING, { days });
  }

  /** 跨端接续可用，vars 支持 `device` / `book` / `page`。 */
  static handoffAvailable(device: string, book: string, page: number): NotificationContent {
    return render(HANDOFF_AVAILABLE, { device, book, page });
  }

  /** 新书上架，vars 支持 `book` / `author`。 */
  static newBookReleased(book: string, author: string): NotificationContent {
    return render(NEW_BOOK_RELEASED, { book, author });
  }

  /** 暴露内部推断（测试用）。 */
  static inferSlot(date?: Date): ReadingTimeSlot {
    return inferSlot(date);
  }
}
