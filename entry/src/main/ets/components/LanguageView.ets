import { LANG_EN, LANG_JA, LANG_SYSTEM, LANG_ZH, LANG_ZH_HANT } from '../model/LanguageStore'

@Component
export struct LanguageView {
  @Prop @Watch('syncLanguage') language: number = LANG_SYSTEM
  @Prop transparentBg: boolean = false
  onSelect: (mode: number) => void = (mode: number): void => {
  }
  @State selectedLanguage: number = LANG_SYSTEM

  aboutToAppear(): void {
    this.syncLanguage()
  }

  syncLanguage(): void {
    this.selectedLanguage = this.language
  }

  private selectLanguage(mode: number): void {
    if (this.selectedLanguage === mode) {
      return
    }
    this.selectedLanguage = mode
    this.onSelect(mode)
  }

  @Builder
  languageRow(mode: number, label: Resource, subtitle: Resource) {
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

        if (this.selectedLanguage === mode) {
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
    .accessibilityChecked(this.selectedLanguage === mode)
    .onClick((): void => this.selectLanguage(mode))
  }

  build() {
    Row() {
      List({ space: 12 }) {
        ListItem() {
          this.languageRow(LANG_SYSTEM, $r('app.string.settings_language_system'),
            $r('app.string.settings_language_system_hint'))
        }

        ListItem() {
          this.languageRow(LANG_ZH, $r('app.string.settings_language_zh'),
            $r('app.string.settings_language_zh_hint'))
        }

        ListItem() {
          this.languageRow(LANG_ZH_HANT, $r('app.string.settings_language_zh_hant'),
            $r('app.string.settings_language_zh_hant_hint'))
        }

        ListItem() {
          this.languageRow(LANG_EN, $r('app.string.settings_language_en'),
            $r('app.string.settings_language_en_hint'))
        }

        ListItem() {
          this.languageRow(LANG_JA, $r('app.string.settings_language_ja'),
            $r('app.string.settings_language_ja_hint'))
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
