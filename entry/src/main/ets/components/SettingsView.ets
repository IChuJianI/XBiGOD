import { HdsListItemCard, SuffixArrow } from '@kit.UIDesignKit'

@Component
export struct SettingsView {
  @Prop languageLabel: string = ''
  @Prop colorModeLabel: string = ''
  @Prop glowLabel: string = ''
  @Prop showAbout: boolean = true
  @Prop transparentBg: boolean = false
  onOpenLanguage: () => void = (): void => {
  }
  onOpenTheme: () => void = (): void => {
  }
  onOpenGlow: () => void = (): void => {
  }
  onOpenAbout: () => void = (): void => {
  }

  @Builder
  groupLabel(text: Resource) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 4 })
  }

  @Builder
  navCard(label: Resource, value: string, action: () => void) {
    HdsListItemCard({
      textItem: {
        primaryText: { text: label },
        secondaryText: { text: value }
      },
      suffixItem: new SuffixArrow({ color: $r('app.color.text_secondary') }),
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 15,
      cardHeight: 60,
      onClick: action
    })
  }

  @Builder
  aboutCard() {
    HdsListItemCard({
      textItem: { primaryText: { text: $r('app.string.about_app_title') } },
      suffixItem: new SuffixArrow({ color: $r('app.color.text_secondary') }),
      cardBackgroundColor: $r('app.color.surface'),
      cardBorderRadius: 15,
      cardHeight: 60,
      onClick: (): void => this.onOpenAbout()
    })
  }

  build() {
    Row() {
      List({ space: 12 }) {
        ListItem() {
          this.groupLabel($r('app.string.settings_group_general'))
        }

        ListItem() {
          this.navCard($r('app.string.settings_language'), this.languageLabel,
            (): void => this.onOpenLanguage())
        }

        ListItem() {
          this.groupLabel($r('app.string.settings_group_appearance'))
        }

        ListItem() {
          this.navCard($r('app.string.settings_dark_mode'), this.colorModeLabel,
            (): void => this.onOpenTheme())
        }

        ListItem() {
          this.navCard($r('app.string.settings_glow'), this.glowLabel,
            (): void => this.onOpenGlow())
        }

        if (this.showAbout) {
          ListItem() {
            this.groupLabel($r('app.string.settings_group_about'))
          }

          ListItem() {
            this.aboutCard()
          }
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
