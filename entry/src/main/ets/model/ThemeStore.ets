import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { window } from '@kit.ArkUI'
import { resourceManager } from '@kit.LocalizationKit'

const PREF_NAME: string = 'app_theme'
const MODE_KEY: string = 'color_mode'

export const MODE_SYSTEM: number = 0
export const MODE_DARK: number = 1
export const MODE_LIGHT: number = 2

export class ThemeStore {
  static load(context: common.UIAbilityContext): number {
    const opts: preferences.Options = { name: PREF_NAME }
    const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
    const raw: number = prefs.getSync(MODE_KEY, MODE_SYSTEM) as number
    if (raw === MODE_DARK || raw === MODE_LIGHT) {
      return raw
    }
    return MODE_SYSTEM
  }

  static apply(context: common.UIAbilityContext, mode: number): void {
    let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    if (mode === MODE_DARK) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } else if (mode === MODE_LIGHT) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    }
    context.getApplicationContext().setColorMode(colorMode)
    ThemeStore.applySystemBarContent(context, mode)
  }

  /** Keeps the status bar glyphs readable against the immersive page background. */
  static applySystemBarContent(context: common.UIAbilityContext, mode: number): void {
    let isDark: boolean
    if (mode === MODE_DARK) {
      isDark = true
    } else if (mode === MODE_LIGHT) {
      isDark = false
    } else {
      isDark = context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK
    }
    ThemeStore.setSystemBarContent(context, isDark)
  }

  static setSystemBarContent(context: common.UIAbilityContext, isDark: boolean): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const props: window.SystemBarProperties = {
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
      }
      win.setWindowSystemBarProperties(props).catch(() => {
      })
    }).catch(() => {
    })
  }

  static save(context: common.UIAbilityContext, mode: number): void {
    const opts: preferences.Options = { name: PREF_NAME }
    const prefs: preferences.Preferences = preferences.getPreferencesSync(context, opts)
    prefs.putSync(MODE_KEY, mode)
    prefs.flush()
  }
}