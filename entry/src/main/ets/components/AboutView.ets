@Component
export struct AboutView {
  @Prop appVersion: string = ''
  @Prop appBundleName: string = ''
  @Prop email: string = ''
  @Prop website: string = ''
  @Prop transparentBg: boolean = false
  onOpenLicenses: () => void = (): void => {
  }
  onCopyEmail: () => void = (): void => {
  }
  onCopyWebsite: () => void = (): void => {
  }

  // 品牌卡自绘留白：图标与文案不再贴边
  @Builder
  brandCard() {
    Row({ space: 14 }) {
      Image($r('app.media.startIcon'))
        .width(48)
        .height(48)
        .borderRadius(14)
        .clip(true)
      Column({ space: 3 }) {
        Text($r('app.string.app_name'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text($r('app.string.app_tagline'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(96)
    .padding({ left: 16, right: 16 })
    .borderRadius(15)
    .backgroundColor($r('app.color.surface'))
    .accessibilityGroup(true)
  }

  // 信息格 1×2：标题在上、值在下，两列等宽
  @Builder
  infoCard(label: Resource, value: ResourceStr) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 60 })
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(15)
    .backgroundColor($r('app.color.surface'))
    .accessibilityGroup(true)
  }

  // 与信息格同款，整行点击复制
  @Builder
  copyCard(label: Resource, value: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(value)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 60 })
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityGroup(true)
    .onClick((): void => action())
  }

  // 与信息格同款，占半格宽
  @Builder
  licensesCard() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Text($r('app.string.settings_licenses'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 60 })
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityGroup(true)
    .onClick((): void => this.onOpenLicenses())
  }

  build() {
    Row() {
      List({ space: 12 }) {
        ListItem() {
          this.brandCard()
        }

        ListItem() {
          Row({ space: 8 }) {
            this.infoCard($r('app.string.about_version'), this.appVersion)
            this.infoCard($r('app.string.about_developer'), $r('app.string.about_developer_name'))
          }
          .width('100%')
        }

        ListItem() {
          Row({ space: 8 }) {
            this.infoCard($r('app.string.about_bundle'), this.appBundleName)
            this.copyCard($r('app.string.about_website'), this.website,
              (): void => this.onCopyWebsite())
          }
          .width('100%')
        }

        ListItem() {
          Row({ space: 8 }) {
            this.copyCard($r('app.string.about_email'), this.email,
              (): void => this.onCopyEmail())
            this.licensesCard()
          }
          .width('100%')
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
