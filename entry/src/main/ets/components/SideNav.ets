import { LayoutSpec } from '../common/LayoutSpec'
import { TabIndex } from '../common/TabIndex'

const ROW_HEIGHT: number = 40
const ABOUT_HOVER_KEY: number = 100

/**
 * 电脑端侧边导航。HdsSideMenu 不开放文字/图标颜色接口，应用内强制深浅色时
 * 配色不跟随，且自身撑满高度会把底部“设置”挤出可视区；这里按 HDS 侧栏尺寸
 * 用官方符号与文本重排，颜色全部走应用令牌。
 */
@Component
export struct SideNav {
  @Prop current: number = 0
  @Prop subPageActive: boolean = false
  @Prop aboutActive: boolean = false
  @State hovered: number = -1
  onSelect: (index: number) => void = (index: number): void => {
  }
  onOpenAbout: () => void = (): void => {
  }

  private isActive(index: number): boolean {
    return !this.subPageActive && this.current === index
  }

  private rowBackground(index: number): ResourceColor {
    if (this.isActive(index)) {
      return $r('app.color.accent_bg')
    }
    if (this.hovered === index) {
      return $r('app.color.surface_secondary')
    }
    return Color.Transparent
  }

  private rowColor(index: number): ResourceColor {
    return this.isActive(index) ? $r('app.color.accent') : $r('app.color.text_primary')
  }

  private rowWeight(index: number): FontWeight {
    return this.isActive(index) ? FontWeight.Medium : FontWeight.Regular
  }

  @Styles
  pressedRow() {
    .backgroundColor($r('app.color.selected_bg'))
  }

  @Builder
  navRow(index: number, label: Resource, symbol: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([this.rowColor(index)])
      Text(label)
        .fontSize(15)
        .fontWeight(this.rowWeight(index))
        .fontColor(this.rowColor(index))
        .maxLines(1)
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 14, right: 14 })
    .borderRadius(LayoutSpec.controlRadius())
    .backgroundColor(this.rowBackground(index))
    .stateStyles({ pressed: this.pressedRow })
    .focusable(true)
    .accessibilityGroup(true)
    .accessibilityText(label)
    .onHover((isHover: boolean): void => {
      if (isHover) {
        this.hovered = index
      } else if (this.hovered === index) {
        this.hovered = -1
      }
    })
    .onClick((): void => this.onSelect(index))
  }

  @Builder
  aboutRow() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(22)
        .fontColor([this.aboutActive ? $r('app.color.accent') : $r('app.color.text_primary')])
      Text($r('app.string.settings_group_about'))
        .fontSize(15)
        .fontWeight(this.aboutActive ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.aboutActive ? $r('app.color.accent') : $r('app.color.text_primary'))
        .maxLines(1)
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 14, right: 14 })
    .borderRadius(LayoutSpec.controlRadius())
    .backgroundColor(this.aboutActive ? $r('app.color.accent_bg')
      : (this.hovered === ABOUT_HOVER_KEY ? $r('app.color.surface_secondary') : Color.Transparent))
    .stateStyles({ pressed: this.pressedRow })
    .focusable(true)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.settings_group_about'))
    .onHover((isHover: boolean): void => {
      if (isHover) {
        this.hovered = ABOUT_HOVER_KEY
      } else if (this.hovered === ABOUT_HOVER_KEY) {
        this.hovered = -1
      }
    })
    .onClick((): void => this.onOpenAbout())
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.startIcon'))
          .width(38)
          .height(38)
          .borderRadius(11)
          .clip(true)
        Column({ space: 2 }) {
          Text($r('app.string.app_name'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
          Text($r('app.string.app_tagline'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 18 })

      Scroll() {
        Column({ space: 4 }) {
          this.navRow(TabIndex.HOME, $r('app.string.tab_home'), $r('sys.symbol.house'))
          this.navRow(TabIndex.CONVERT, $r('app.string.tab_convert'), $r('sys.symbol.arrow_down_square'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)

      this.aboutRow()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, top: 16, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
  }
}
