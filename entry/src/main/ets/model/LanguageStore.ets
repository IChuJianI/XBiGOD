import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { i18n } from '@kit.LocalizationKit'

const PREF_NAME: string = 'app_language'
const MODE_KEY: string = 'language_mode'

const TAG_ZH: string = 'zh-Hans'
const TAG_ZH_HANT: string = 'zh-Hant'
const TAG_EN: string = 'en-Latn-US'
const TAG_JA: string = 'ja'

export const LANG_SYSTEM: number = 0
export const LANG_ZH: number = 1
export const LANG_EN: number = 2
export const LANG_ZH_HANT: number = 3
export const LANG_JA: number = 4

export class LanguageStore {
  static load(context: common.UIAbilityContext): number {
    const opts: preferences.Options = { name: PREF_NAME }
    const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
    const raw: number = prefs.getSync(MODE_KEY, LANG_SYSTEM) as number
    if (raw === LANG_ZH || raw === LANG_ZH_HANT || raw === LANG_EN || raw === LANG_JA) {
      return raw
    }
    return LANG_SYSTEM
  }

  /** 应用偏好语言在冷启动时决定加载哪套资源，需在 loadContent 前调用 */
  static applyAtLaunch(mode: number): void {
    try {
      i18n.System.setAppPreferredLanguage(mode === LANG_SYSTEM ? 'default' : LanguageStore.tag(mode))
    } catch (_e) {
      // ignore invalid language tags and keep the system language
    }
  }

  /** 运行中切换语言：立即重解析资源并刷新界面 */
  static applyNow(context: common.UIAbilityContext, mode: number): void {
    try {
      context.getApplicationContext().setLanguage(LanguageStore.tag(mode))
    } catch (_e) {
      // ignore
    }
  }

  static save(context: common.UIAbilityContext, mode: number): void {
    const opts: preferences.Options = { name: PREF_NAME }
    const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
    prefs.putSync(MODE_KEY, mode)
    prefs.flush()
  }

  private static tag(mode: number): string {
    if (mode === LANG_ZH) {
      return TAG_ZH
    }
    if (mode === LANG_ZH_HANT) {
      return TAG_ZH_HANT
    }
    if (mode === LANG_EN) {
      return TAG_EN
    }
    if (mode === LANG_JA) {
      return TAG_JA
    }
    return i18n.System.getSystemLanguage()
  }
}
