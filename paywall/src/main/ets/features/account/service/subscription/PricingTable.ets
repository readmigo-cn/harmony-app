/**
 * PricingTable.ets — W17-C7 区域定价 + 套餐元数据
 *
 * Source of truth：套餐 ID / 价格 / 推荐等级 / 试用期 / 功能列表。
 * Paywall / Subscriptions 页统一从这里取，避免散落在各处。
 *
 * 区域：
 *   - CN   人民币（HMS IAP / 微信 / 支付宝）
 *   - HMT  港澳台（HKD/TWD，预留，未启用）
 *   - INTL 海外（USD，预留占位，海外版走 readmigo iOS/Android）
 *
 * 推荐等级 recommendLevel 数值越高排序越靠前 / 视觉越突出。
 */

import { SubscriptionPlan } from '../../../../api/subscription/SubscriptionApi';

// ─── 类型 ────────────────────────────────────────

export type PlanTier = 'free' | 'pro_monthly' | 'pro_yearly' | 'premium_monthly';
export type Region = 'CN' | 'HMT' | 'INTL';
export type Currency = 'CNY' | 'HKD' | 'TWD' | 'USD';

/** 单功能行（用于套餐对比表）。 */
export interface FeatureRow {
  key: string;
  label: string;
  /** 各 tier 是否包含该功能。 */
  free: boolean;
  proMonthly: boolean;
  proYearly: boolean;
  premiumMonthly: boolean;
}

/** 区域定价。 */
export interface RegionalPrice {
  currency: Currency;
  /** 显示价（含符号）。 */
  display: string;
  /** 数字（用于换算 / 排序）。 */
  amount: number;
  /** 原价（划线价）；无折扣时为 null。 */
  originalDisplay: string | null;
  originalAmount: number | null;
}

/** 套餐元数据。 */
export interface PlanMeta {
  tier: PlanTier;
  /** 后端 plan id（free 为 null）。 */
  plan: SubscriptionPlan | null;
  /** HMS IAP product id；free 为 null。 */
  productId: string | null;
  title: string;
  subtitle: string;
  /** 周期文案：'月' / '年' / '永久'。 */
  cycleLabel: string;
  /** 试用天数；0 表示无试用。 */
  trialDays: number;
  /** 推荐等级（0 = 不推荐，1 = 一般，2 = 强烈推荐）。 */
  recommendLevel: number;
  /** 推荐徽章文案；recommendLevel = 0 时为空。 */
  badge: string;
  /** 折扣文案（仅展示用）；无折扣返回空串。 */
  discountLabel: string;
  /** 区域价。 */
  prices: Record<Region, RegionalPrice>;
  /** 价格亮点列表（首屏展示）。 */
  highlights: string[];
}

// ─── 功能对比表 ──────────────────────────────────

export const FEATURE_ROWS: FeatureRow[] = [
  { key: 'books_free',      label: '免费图书',
    free: true,  proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'books_premium',   label: '全本图书 / 出版社授权书',
    free: false, proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'ai_lookup',       label: 'AI 划词解释（无限）',
    free: false, proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'ai_translate',    label: '段落翻译 / 双语对照',
    free: false, proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'progress_sync',   label: '多端进度同步',
    free: true,  proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'flashcards',      label: 'AI 闪卡 / 词族 / 弱点分析',
    free: false, proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'tts_basic',       label: '基础 TTS 朗读',
    free: true,  proMonthly: true,  proYearly: true,  premiumMonthly: true },
  { key: 'tts_premium',     label: '高级真人 TTS（多音色）',
    free: false, proMonthly: false, proYearly: false, premiumMonthly: true },
  { key: 'audiobook_unlim', label: '听书无限时长',
    free: false, proMonthly: false, proYearly: false, premiumMonthly: true },
  { key: 'priority_support',label: '优先客服支持',
    free: false, proMonthly: false, proYearly: true,  premiumMonthly: true },
];

// ─── 套餐元数据（CN 区为主，HMT/INTL 占位）──────

const PLAN_FREE: PlanMeta = {
  tier: 'free',
  plan: null,
  productId: null,
  title: '免费版',
  subtitle: '常用功能 + 基础内容',
  cycleLabel: '永久',
  trialDays: 0,
  recommendLevel: 0,
  badge: '',
  discountLabel: '',
  prices: {
    CN:   { currency: 'CNY', display: '￥0',  amount: 0, originalDisplay: null, originalAmount: null },
    HMT:  { currency: 'HKD', display: 'HK$0', amount: 0, originalDisplay: null, originalAmount: null },
    INTL: { currency: 'USD', display: '$0',   amount: 0, originalDisplay: null, originalAmount: null },
  },
  highlights: ['免费图书阅读', '基础 TTS 朗读', '多端进度同步'],
};

const PLAN_PRO_MONTHLY: PlanMeta = {
  tier: 'pro_monthly',
  plan: 'pro_monthly',
  productId: 'cn.readmigo.harmony.pro_monthly',
  title: 'Pro 月订阅',
  subtitle: '解锁 AI 学习与全本图书',
  cycleLabel: '月',
  trialDays: 0,
  recommendLevel: 1,
  badge: '',
  discountLabel: '',
  prices: {
    CN:   { currency: 'CNY', display: '￥35',   amount: 35,    originalDisplay: null, originalAmount: null },
    HMT:  { currency: 'HKD', display: 'HK$38',  amount: 38,    originalDisplay: null, originalAmount: null },
    INTL: { currency: 'USD', display: '$4.99',  amount: 4.99,  originalDisplay: null, originalAmount: null },
  },
  highlights: ['全本图书畅读', 'AI 划词无限次', 'AI 闪卡 / 词族'],
};

const PLAN_PRO_YEARLY: PlanMeta = {
  tier: 'pro_yearly',
  plan: 'pro_yearly',
  productId: 'cn.readmigo.harmony.pro_yearly',
  title: 'Pro 年订阅',
  subtitle: '一年无忧，平均每月仅 ￥17.75',
  cycleLabel: '年',
  trialDays: 7,
  recommendLevel: 2,
  badge: '最划算 -50%',
  discountLabel: '原价 ￥420，立省 ￥207',
  prices: {
    CN:   { currency: 'CNY', display: '￥213',   amount: 213,   originalDisplay: '￥420',   originalAmount: 420   },
    HMT:  { currency: 'HKD', display: 'HK$228',  amount: 228,   originalDisplay: 'HK$456',  originalAmount: 456   },
    INTL: { currency: 'USD', display: '$29.99',  amount: 29.99, originalDisplay: '$59.88',  originalAmount: 59.88 },
  },
  highlights: ['Pro 全部功能', '7 天免费试用', '优先客服支持', '相比月付立省 50%'],
};

const PLAN_PREMIUM_MONTHLY: PlanMeta = {
  tier: 'premium_monthly',
  plan: 'premium_monthly',
  productId: 'cn.readmigo.harmony.premium_monthly',
  title: 'Premium 月订阅',
  subtitle: 'Pro 全部 + 高级 TTS + 听书无限',
  cycleLabel: '月',
  trialDays: 0,
  recommendLevel: 1,
  badge: '听书发烧友',
  discountLabel: '',
  prices: {
    CN:   { currency: 'CNY', display: '￥71',   amount: 71,    originalDisplay: null, originalAmount: null },
    HMT:  { currency: 'HKD', display: 'HK$78',  amount: 78,    originalDisplay: null, originalAmount: null },
    INTL: { currency: 'USD', display: '$9.99',  amount: 9.99,  originalDisplay: null, originalAmount: null },
  },
  highlights: ['Pro 全部功能', '高级真人 TTS（多音色）', '听书无限时长', '听书离线下载'],
};

const ALL_PLANS: PlanMeta[] = [PLAN_FREE, PLAN_PRO_MONTHLY, PLAN_PRO_YEARLY, PLAN_PREMIUM_MONTHLY];

// ─── 公开 API ────────────────────────────────────

export class PricingTable {
  /**
   * 默认区域。当前 HarmonyOS 包仅在中国区上架，硬编码 CN。
   * 后续若需多区域，可改为读取系统 region 或 UserStore.locale。
   */
  static getRegion(): Region {
    return 'CN';
  }

  /** 全部套餐（按推荐等级降序）。 */
  static listPlans(): PlanMeta[] {
    return ALL_PLANS.slice().sort((a, b) => b.recommendLevel - a.recommendLevel);
  }

  /** 付费套餐（不含 free）。 */
  static listPaidPlans(): PlanMeta[] {
    return PricingTable.listPlans().filter((p) => p.tier !== 'free');
  }

  static getPlan(tier: PlanTier): PlanMeta | null {
    for (let i = 0; i < ALL_PLANS.length; i++) {
      if (ALL_PLANS[i].tier === tier) return ALL_PLANS[i];
    }
    return null;
  }

  static getPlanByProductId(productId: string): PlanMeta | null {
    for (let i = 0; i < ALL_PLANS.length; i++) {
      if (ALL_PLANS[i].productId === productId) return ALL_PLANS[i];
    }
    return null;
  }

  /** 当前区域的展示价。 */
  static getPrice(tier: PlanTier, region: Region = PricingTable.getRegion()): RegionalPrice | null {
    const meta = PricingTable.getPlan(tier);
    return meta ? meta.prices[region] : null;
  }

  /** 推荐套餐（recommendLevel 最高）。 */
  static getRecommended(): PlanMeta {
    const plans = PricingTable.listPaidPlans();
    let best = plans[0];
    for (let i = 1; i < plans.length; i++) {
      if (plans[i].recommendLevel > best.recommendLevel) best = plans[i];
    }
    return best;
  }

  /** 套餐功能对比表（Paywall 渲染勾选列表用）。 */
  static featureRows(): FeatureRow[] {
    return FEATURE_ROWS;
  }

  /**
   * 简易货币换算（仅展示参考，结算以平台为准）。
   * 1 USD = 7.1 CNY；1 HKD = 0.92 CNY。
   */
  static toCNY(amount: number, currency: Currency): number {
    if (currency === 'CNY') return amount;
    if (currency === 'USD') return Math.round(amount * 7.1 * 100) / 100;
    if (currency === 'HKD') return Math.round(amount * 0.92 * 100) / 100;
    if (currency === 'TWD') return Math.round(amount * 0.23 * 100) / 100;
    return amount;
  }

  /** 试用文案。 */
  static trialText(meta: PlanMeta): string {
    if (meta.trialDays <= 0) return '';
    return `前 ${meta.trialDays} 天免费试用，到期自动续费`;
  }

  /** 协议文案 i18n（中文）。 */
  static i18n() {
    return {
      title:           '解锁 Pro 完整体验',
      subtitle:        '选择适合你的方案，随时取消',
      btnSubscribe:    '立即订阅',
      btnRestore:      '恢复购买',
      btnCancel:       '稍后再说',
      payHmsIap:       '华为支付',
      payWeChat:       '微信支付',
      payAlipay:       '支付宝',
      legalAgreement:  '订阅协议',
      legalAutoRenew:  '自动续费协议',
      legalNote:       '订阅将自动续费，可在订阅管理中取消',
      paySelectorTitle: '选择支付方式',
      compareTableTitle: '功能对比',
    };
  }
}
