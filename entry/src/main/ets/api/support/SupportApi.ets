/**
 * SupportApi.ets — W19-C1+C2 反馈 / 工单 API
 *
 * 后端 endpoint 占位（W11+ 由 server-cn 实现）：
 *   POST   /api/v1/support/tickets               提交反馈，返回新建工单
 *   GET    /api/v1/support/tickets               拉取当前用户工单列表（按 filter）
 *   GET    /api/v1/support/tickets/:id           工单详情（含消息时间线）
 *   POST   /api/v1/support/tickets/:id/replies   用户追问
 *   POST   /api/v1/support/tickets/:id/close     用户关闭工单
 *   POST   /api/v1/support/tickets/:id/rate      工单关闭后满意度评分
 *
 * 工单状态机：
 *   open       初始 / 用户追问后回到 open
 *      └─→ pending   客服已回复，等待用户操作
 *               └─→ resolved 客服标记或满意度评分 ≥4
 *                          └─→ closed   用户主动关闭（terminal）
 *      └─→ closed   用户直接关闭（terminal）
 */

import { HttpClient } from '../../api/client/HttpClient';

// ─────────────────────────────────────────────
// 类型定义
// ─────────────────────────────────────────────

/** 工单类别（与表单选择器对齐） */
export type TicketCategory =
  | 'bug'        // bug
  | 'feature'    // 功能建议
  | 'content'    // 内容问题
  | 'payment'    // 支付
  | 'account'    // 账号
  | 'other';     // 其它

/** 工单状态机 */
export type TicketStatus =
  | 'open'       // 待客服处理
  | 'pending'    // 已回复，等用户操作
  | 'resolved'   // 已解决（客服标记 / 满意度 ≥4）
  | 'closed';    // 已关闭（terminal）

/** 工单消息发送方 */
export type TicketSenderRole = 'user' | 'agent' | 'system';

/** 提交反馈时附带的环境上下文（用户可勾选去掉） */
export interface TicketContext {
  appVersion?: string;
  os?: string;          // e.g. 'HarmonyOS NEXT 5.0'
  deviceModel?: string; // e.g. 'HUAWEI Mate 60 Pro'
  userId?: string;
  currentRoute?: string;
  /** 最近 30 行日志（明文，用户可决定是否上送） */
  recentLogs?: string[];
}

/** 提交反馈 payload */
export interface SubmitTicketPayload {
  category: TicketCategory;
  title: string;            // <= 50 字
  description: string;      // <= 500 字
  /** 已上传截图的服务端 URL 列表（最多 3 张，本地路径需先转为 URL） */
  screenshots?: string[];
  /** 环境上下文（用户勾选） */
  context?: TicketContext;
}

/** 单条工单消息 */
export interface TicketMessage {
  id: string;
  ticketId: string;
  sender: TicketSenderRole;
  content: string;
  attachments: string[];
  createdAt: string; // ISO
}

/** 工单实体（含消息时间线） */
export interface Ticket {
  id: string;
  userId: string;
  category: TicketCategory;
  title: string;
  description: string;
  screenshots: string[];
  context: TicketContext | null;
  status: TicketStatus;
  /** 1-5 星，未评分为 null */
  rating: number | null;
  messages: TicketMessage[];
  createdAt: string;
  updatedAt: string;
  /** 最后一条消息时间，用于列表排序 */
  lastReplyAt: string | null;
}

/** 列表过滤器 */
export interface ListTicketsQuery {
  /** 'open' = 进行中（open / pending） / 'resolved' = 已解决 / 'all' = 全部 */
  filter?: 'open' | 'resolved' | 'all';
  page?: number;
  limit?: number;
}

export interface ListTicketsResp {
  items: Ticket[];
  total: number;
}

export interface ReplyTicketPayload {
  content: string;
  attachments?: string[];
}

export interface RateTicketPayload {
  rating: number; // 1-5
  comment?: string;
}

// ─────────────────────────────────────────────
// SupportApi
// ─────────────────────────────────────────────

export class SupportApi {
  /** 提交反馈，返回新建工单（含 id），调用方可直接跳到 TicketDetail */
  static submitTicket(payload: SubmitTicketPayload): Promise<Ticket> {
    return HttpClient.post<Ticket>('/support/tickets', payload);
  }

  /** 工单列表 */
  static listTickets(query?: ListTicketsQuery): Promise<ListTicketsResp> {
    const q: Record<string, string | number> = {};
    if (query?.filter) q.filter = query.filter;
    if (query?.page !== undefined) q.page = query.page;
    if (query?.limit !== undefined) q.limit = query.limit;
    return HttpClient.get<ListTicketsResp>('/support/tickets', q);
  }

  /** 工单详情 */
  static getTicket(id: string): Promise<Ticket> {
    return HttpClient.get<Ticket>(`/support/tickets/${id}`);
  }

  /** 用户追问 */
  static replyTicket(id: string, payload: ReplyTicketPayload): Promise<TicketMessage> {
    return HttpClient.post<TicketMessage>(`/support/tickets/${id}/replies`, payload);
  }

  /** 用户主动关闭工单 */
  static closeTicket(id: string): Promise<Ticket> {
    return HttpClient.post<Ticket>(`/support/tickets/${id}/close`);
  }

  /** 满意度评分（关闭工单时弹出） */
  static rateTicket(id: string, payload: RateTicketPayload): Promise<Ticket> {
    return HttpClient.post<Ticket>(`/support/tickets/${id}/rate`, payload);
  }
}

// ─────────────────────────────────────────────
// UI 辅助：类别 / 状态文案
// ─────────────────────────────────────────────

export function ticketCategoryLabel(c: TicketCategory): string {
  switch (c) {
    case 'bug': return 'Bug 反馈';
    case 'feature': return '功能建议';
    case 'content': return '内容问题';
    case 'payment': return '支付问题';
    case 'account': return '账号问题';
    case 'other': return '其它';
  }
}

export function ticketCategoryIcon(c: TicketCategory): string {
  switch (c) {
    case 'bug': return '🐞';
    case 'feature': return '💡';
    case 'content': return '📖';
    case 'payment': return '💳';
    case 'account': return '👤';
    case 'other': return '💬';
  }
}

export function ticketStatusLabel(s: TicketStatus): string {
  switch (s) {
    case 'open': return '待处理';
    case 'pending': return '客服已回复';
    case 'resolved': return '已解决';
    case 'closed': return '已关闭';
  }
}

/** 列表 / 详情 顶部状态条颜色 hex（外部用 useColor 包一层即可） */
export function ticketStatusColor(s: TicketStatus): string {
  switch (s) {
    case 'open': return '#FF9500';      // 橙
    case 'pending': return '#007AFF';   // 蓝
    case 'resolved': return '#34C759';  // 绿
    case 'closed': return '#8E8E93';    // 灰
  }
}
