import { deviceInfo } from '@kit.BasicServicesKit'

/**
 * Adaptive layout values following the HarmonyOS window size classes:
 * compact (<600vp), medium (600-840vp) and expanded (>=840vp).
 */
export class LayoutSpec {
  static readonly BREAKPOINT_MD: number = 600
  static readonly BREAKPOINT_LG: number = 840

  static readonly MARGIN_COMPACT: number = 16
  static readonly MARGIN_MEDIUM: number = 24
  static readonly MARGIN_EXPANDED: number = 32

  static readonly CONTENT_MAX_WIDTH_COMPACT: number = 720
  static readonly CONTENT_MAX_WIDTH_EXPANDED: number = 840

  static readonly SIDEBAR_WIDTH: number = 280

  static readonly TITLE_BAR_HEIGHT: number = 56
  static readonly TAB_BAR_WIDTH_MEDIUM: number = 360
  static readonly TAB_BAR_WIDTH_LARGE: number = 420
  static readonly TAB_BAR_SIDE_MARGIN: number = 16
  static readonly TAB_BAR_BOTTOM_GAP: number = 16
  static readonly COMPACT_BOTTOM_INSET: number = 96

  static readonly SPACING_COMPACT: number = 16
  static readonly SPACING_EXPANDED: number = 24

  static readonly TOUCH_TARGET: number = 40

  /** 与 WFun 搜索栏一致：电脑小圆角，其余设备全圆角 */
  static controlRadius(): number {
    return deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1 ? 8 : 20
  }
}