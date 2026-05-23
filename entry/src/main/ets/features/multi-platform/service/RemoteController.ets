import window from '@ohos.window';
import { KeyEvent, KeyCode, KeyAction } from '@ohos.multimodalInput.keyEvent';

/**
 * RemoteController — W15-C3 智慧屏遥控器键位映射
 *
 * 设计要点：
 *   - 焦点导航（DPAD_UP/DOWN/LEFT/RIGHT）由 ArkUI 自身的 focus chain 处理，
 *     业务侧不拦截，只在调试日志中打点。
 *   - SELECT (KEYCODE_DPAD_CENTER / ENTER / NUMPAD_ENTER) → 触发当前 focused
 *     element 的 onClick，ArkUI 默认行为，业务侧透传。
 *   - BACK (KEYCODE_BACK / ESC) → 走 onBackPressed，由各页面 router.pop。
 *   - MENU (KEYCODE_MENU) → 弹出阅读 / 听书设置面板，统一广播事件。
 *   - PLAY_PAUSE (KEYCODE_MEDIA_PLAY_PAUSE / KEYCODE_MEDIA_PLAY / PAUSE) →
 *     无论焦点在哪，立刻广播 audio toggle，AudioPlayerStore 监听执行。
 *   - 数字键 0-9 / VOLUME → 透传给系统。
 *
 * 所有 key 事件以「订阅器（callback list）」模式分发，组件 willMount 时
 * RemoteController.listen(cb)，willUnmount 时 unlisten(cb)。
 */

export type RemoteKey =
  | 'UP' | 'DOWN' | 'LEFT' | 'RIGHT'
  | 'SELECT' | 'BACK' | 'MENU' | 'PLAY_PAUSE'
  | 'CHANNEL_UP' | 'CHANNEL_DOWN'
  | 'VOLUME_UP' | 'VOLUME_DOWN';

export type RemoteListener = (key: RemoteKey, raw: KeyEvent) => boolean;

const TAG = 'RemoteController';
const listeners: RemoteListener[] = [];

function mapKeyCode(code: number): RemoteKey | null {
  switch (code) {
    case KeyCode.KEYCODE_DPAD_UP:    return 'UP';
    case KeyCode.KEYCODE_DPAD_DOWN:  return 'DOWN';
    case KeyCode.KEYCODE_DPAD_LEFT:  return 'LEFT';
    case KeyCode.KEYCODE_DPAD_RIGHT: return 'RIGHT';
    case KeyCode.KEYCODE_DPAD_CENTER:
    case KeyCode.KEYCODE_ENTER:
    case KeyCode.KEYCODE_NUMPAD_ENTER:
      return 'SELECT';
    case KeyCode.KEYCODE_BACK:
    case KeyCode.KEYCODE_ESCAPE:
      return 'BACK';
    case KeyCode.KEYCODE_MENU:       return 'MENU';
    case KeyCode.KEYCODE_MEDIA_PLAY_PAUSE:
    case KeyCode.KEYCODE_MEDIA_PLAY:
    case KeyCode.KEYCODE_MEDIA_PAUSE:
      return 'PLAY_PAUSE';
    case KeyCode.KEYCODE_CHANNEL_UP:   return 'CHANNEL_UP';
    case KeyCode.KEYCODE_CHANNEL_DOWN: return 'CHANNEL_DOWN';
    case KeyCode.KEYCODE_VOLUME_UP:    return 'VOLUME_UP';
    case KeyCode.KEYCODE_VOLUME_DOWN:  return 'VOLUME_DOWN';
    default: return null;
  }
}

export class RemoteController {
  private win: window.Window | null = null;

  /** 在 SmartScreenAbility.onWindowStageCreate 中调用一次。 */
  attach(win: window.Window): void {
    this.win = win;
    try {
      win.on('keyboardEvent', (event: KeyEvent) => {
        if (event.action !== KeyAction.DOWN) return; // 只处理按下
        const key = mapKeyCode(event.keyCode);
        if (!key) return;
        console.info(`${TAG} key=${key} code=${event.keyCode}`);
        // 派发：第一个返回 true 的 listener 截获事件
        for (let i = listeners.length - 1; i >= 0; i--) {
          const handled = listeners[i](key, event);
          if (handled) return;
        }
      });
    } catch (e) {
      console.warn(`${TAG} attach failed: ${(e as Error).message}`);
    }
  }

  detach(): void {
    if (this.win) {
      try { this.win.off('keyboardEvent'); } catch (_) {}
      this.win = null;
    }
  }

  /** 组件订阅遥控器（aboutToAppear 调用，返回 unlisten 函数）。 */
  static listen(cb: RemoteListener): () => void {
    listeners.push(cb);
    return () => {
      const idx = listeners.indexOf(cb);
      if (idx >= 0) listeners.splice(idx, 1);
    };
  }
}

/**
 * FocusManager — 简易焦点辅助，给视觉焦点框提供 1.05 scale + brand border。
 * ArkUI focusable + onFocus/onBlur 已经原生支持，这里只统一暴露样式常量。
 */
export const FocusStyle = {
  scale: { x: 1.05, y: 1.05 },
  borderWidth: 4,
  borderRadius: 16,
  duration: 180,
} as const;
