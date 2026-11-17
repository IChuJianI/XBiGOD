import { MODE_DARK, MODE_LIGHT, MODE_SYSTEM } from '../model/ThemeStore'

@Component
export struct ColorModeView {
  @Prop @Watch('syncColorMode') colorMode: number = MODE_SYSTEM
  @Prop transparentBg: boolean = false
  onSelect: (mode: number) => void = (mode: number): void => {
  }
  @State selectedMode: number = MODE_SYSTEM

  aboutToAppear(): void {
    this.syncColorMode()
  }

  syncColorMode(): void {
    this.selectedMode = this.colorMode
  }

  private selectMode(mode: number): void {
    if (this.selectedMode === mode) {
      return
    }
    this.selectedMode = mode
    this.onSelect(mode)
  }

  @Builder
  modeRow(mode: number, label: Resource, subtitle: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Column({ space: 2 }) {
          Text(label)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.selectedMode === mode) {
          Stack() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(13)
              .fontColor([Color.White])
          }
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor($r('app.color.accent'))
          .margin({ left: 12 })
        } else {
          Row()
            .width(22)
            .height(22)
            .margin({ left: 12 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityRole(AccessibilityRoleType.RADIO)
    .accessibilityChecked(this.selectedMode === mode)
    .onClick((): void => this.selectMode(mode))
  }

  build() {
    Row() {
      List({ space: 12 }) {
        ListItem() {
          this.modeRow(MODE_SYSTEM, $r('app.string.settings_dark_mode_system'),
            $r('app.string.settings_dark_mode_system_hint'))
        }

        ListItem() {
          this.modeRow(MODE_LIGHT, $r('app.string.settings_dark_mode_off'),
            $r('app.string.settings_dark_mode_off_hint'))
        }

        ListItem() {
          this.modeRow(MODE_DARK, $r('app.string.settings_dark_mode_on'),
            $r('app.string.settings_dark_mode_on_hint'))
        }

        ListItem() {
          Text($r('app.string.settings_dark_mode_note'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, top: 10 })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 800 })
      .height('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.transparentBg ? Color.Transparent : $r('app.color.page_bg'))
  }
}
