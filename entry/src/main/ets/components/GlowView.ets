import { uiMaterial } from '@kit.ArkUI'
import { GLOW_CLEAR, GLOW_SOFT, GLOW_STANDARD } from '../model/GlowStore'

@Component
export struct GlowView {
  @Prop @Watch('syncGlow') glowLevel: number = GLOW_STANDARD
  @Prop transparentBg: boolean = false
  onSelect: (level: number) => void = (level: number): void => {
  }
  @State selectedLevel: number = GLOW_STANDARD

  aboutToAppear(): void {
    this.syncGlow()
  }

  syncGlow(): void {
    this.selectedLevel = this.glowLevel
  }

  private selectLevel(level: number): void {
    if (this.selectedLevel === level) {
      return
    }
    this.selectedLevel = level
    this.onSelect(level)
  }

  private noteText(): Resource {
    if (uiMaterial.isImmersiveMaterialSupported()) {
      return $r('app.string.settings_glow_note')
    }
    return $r('app.string.settings_glow_unsupported_note')
  }

  @Builder
  levelRow(level: number, label: Resource, subtitle: Resource) {
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

        if (this.selectedLevel === level) {
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
    .accessibilityChecked(this.selectedLevel === level)
    .onClick((): void => this.selectLevel(level))
  }

  build() {
    Row() {
      List({ space: 12 }) {
        ListItem() {
          this.levelRow(GLOW_SOFT, $r('app.string.settings_glow_soft'),
            $r('app.string.settings_glow_soft_hint'))
        }

        ListItem() {
          this.levelRow(GLOW_STANDARD, $r('app.string.settings_glow_standard'),
            $r('app.string.settings_glow_standard_hint'))
        }

        ListItem() {
          this.levelRow(GLOW_CLEAR, $r('app.string.settings_glow_clear'),
            $r('app.string.settings_glow_clear_hint'))
        }

        ListItem() {
          Text(this.noteText())
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
