import {
  GOD2ISO_CREDIT,
  GOD2ISO_LICENSE_TEXT,
  ISO2GOD_PROJECT,
  MIT_COMPONENTS,
  MIT_COPYRIGHTS,
  MIT_LICENSE_TEXT,
  RUST_STD_UNICODE_COPYRIGHT,
  UNICODE_COPYRIGHT,
  UNICODE_LICENSE_TEXT,
  XBIGOD_PROJECT
} from '../model/LicenseData'

@Component
export struct LicensesPage {
  @Prop pagePadding: number = 16
  @Prop contentMaxWidth: number = 840
  @Prop bottomInset: number = 16
  @State showMit: boolean = false
  @State showUnicode: boolean = false
  @State showGod2iso: boolean = false

  build() {
    Scroll() {
      Column() {
        Column({ space: 8 }) {
          this.projectsCard()
          this.mitCard()
          this.unicodeCard()
          this.god2isoCard()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.contentMaxWidth })
      }
      .width('100%')
      .padding({
        left: this.pagePadding,
        right: this.pagePadding,
        top: this.pagePadding,
        bottom: this.bottomInset
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  projectsCard() {
    Column({ space: 10 }) {
      Text($r('app.string.licenses_projects'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      this.textBlock($r('app.string.licenses_project_self'), XBIGOD_PROJECT)
      this.textBlock($r('app.string.licenses_project_upstream'), ISO2GOD_PROJECT + '\n\n' + GOD2ISO_CREDIT)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
  }

  @Builder
  mitCard() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('MIT License')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.licenses_mit_summary'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.showMit ? $r('app.string.licenses_collapse') : $r('app.string.licenses_expand'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
            .rotate({ angle: this.showMit ? 180 : 0 })
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 60 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(0)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        pressed: {
          .backgroundColor($r('app.color.surface_secondary'))
        }
      })
      .onClick(() => {
        this.showMit = !this.showMit
      })

      if (this.showMit) {
        Divider()
          .color($r('app.color.divider'))
        Column({ space: 10 }) {
          this.textBlock($r('app.string.licenses_components_versions'), MIT_COMPONENTS.join(', '))
          this.textBlock($r('app.string.licenses_copyright_notices'), MIT_COPYRIGHTS.join('\n'))
          this.textBlock($r('app.string.licenses_full_text'), MIT_LICENSE_TEXT)
          Text($r('app.string.licenses_mit_note'))
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text($r('app.string.licenses_reference_line'))
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .clip(true)
  }

  @Builder
  unicodeCard() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('Unicode License V3')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.licenses_unicode_scope'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.showUnicode ? $r('app.string.licenses_collapse') : $r('app.string.licenses_expand'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
            .rotate({ angle: this.showUnicode ? 180 : 0 })
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 60 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(0)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        pressed: {
          .backgroundColor($r('app.color.surface_secondary'))
        }
      })
      .onClick(() => {
        this.showUnicode = !this.showUnicode
      })

      if (this.showUnicode) {
        Divider()
          .color($r('app.color.divider'))
        Column({ space: 10 }) {
          this.textBlock($r('app.string.licenses_copyright_notices'),
            UNICODE_COPYRIGHT + '\n' + 'Rust Standard Library  ·  ' + RUST_STD_UNICODE_COPYRIGHT)
          this.textBlock($r('app.string.licenses_full_text'), UNICODE_LICENSE_TEXT)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .clip(true)
  }

  @Builder
  god2isoCard() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('god2iso · CC BY-SA 4.0')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.licenses_god2iso_summary'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.showGod2iso ? $r('app.string.licenses_collapse') : $r('app.string.licenses_expand'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
            .rotate({ angle: this.showGod2iso ? 180 : 0 })
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 60 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(0)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        pressed: {
          .backgroundColor($r('app.color.surface_secondary'))
        }
      })
      .onClick(() => {
        this.showGod2iso = !this.showGod2iso
      })

      if (this.showGod2iso) {
        Divider()
          .color($r('app.color.divider'))
        Column({ space: 10 }) {
          this.textBlock($r('app.string.licenses_copyright_notices'), GOD2ISO_CREDIT)
          Text($r('app.string.licenses_god2iso_scope'))
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          this.textBlock($r('app.string.licenses_full_text'), GOD2ISO_LICENSE_TEXT)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .clip(true)
  }

  @Builder
  textBlock(label: Resource, body: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(body)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
