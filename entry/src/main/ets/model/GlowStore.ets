import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { uiMaterial } from '@kit.ArkUI'

const PREF_NAME: string = 'app_theme'
const GLOW_KEY: string = 'glow_level'

export const GLOW_SOFT: number = 0
export const GLOW_STANDARD: number = 1
export const GLOW_CLEAR: number = 2

/** 沉浸光感档位：系统材质按场景给不同粗细，每档在标题栏、悬浮底栏和半模态上各推一级 */
export class GlowStore {
  static load(context: common.UIAbilityContext): number {
    try {
      const opts: preferences.Options = { name: PREF_NAME }
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
      const raw: number = prefs.getSync(GLOW_KEY, GLOW_STANDARD) as number
      if (raw === GLOW_SOFT || raw === GLOW_CLEAR) {
        return raw
      }
    } catch (_e) {
      // 读取失败时回落到标准档
    }
    return GLOW_STANDARD
  }

  static save(context: common.UIAbilityContext, level: number): void {
    try {
      const opts: preferences.Options = { name: PREF_NAME }
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
      prefs.putSync(GLOW_KEY, level)
      prefs.flushSync()
    } catch (_e) {
      // 持久化失败不影响本次生效
    }
  }

  /** Navigation 标题栏（顶部悬浮场景） */
  static titleStyle(level: number): uiMaterial.ImmersiveStyle {
    return level === GLOW_SOFT
      ? uiMaterial.ImmersiveStyle.REGULAR
      : uiMaterial.ImmersiveStyle.ULTRA_THIN
  }

  /** 悬浮底栏与半模态（底部悬浮场景） */
  static barStyle(level: number): uiMaterial.ImmersiveStyle {
    if (level === GLOW_SOFT) {
      return uiMaterial.ImmersiveStyle.THICK
    }
    if (level === GLOW_CLEAR) {
      return uiMaterial.ImmersiveStyle.ULTRA_THIN
    }
    return uiMaterial.ImmersiveStyle.THIN
  }
}
