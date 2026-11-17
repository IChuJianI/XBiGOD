import { pasteboard } from '@kit.BasicServicesKit'
import {
  GOD2ISO_COPYRIGHT,
  GOD2ISO_CREDIT,
  GOD2ISO_LICENSE_TEXT,
  GOD2ISO_NAME,
  GOD2ISO_URL,
  ISO2GOD_COPYRIGHT,
  ISO2GOD_NAME,
  ISO2GOD_URL,
  MIT_COMPONENTS,
  MIT_COPYRIGHTS,
  MIT_LICENSE_TEXT,
  RUST_STD_UNICODE_COPYRIGHT,
  UNICODE_COPYRIGHT,
  UNICODE_LICENSE_TEXT,
  XBIGOD_COPYRIGHT,
  XBIGOD_NAME,
  XBIGOD_URL
} from '../model/LicenseData'

const SECTION_PROJECTS: number = 0
const SECTION_MIT: number = 1
const SECTION_UNICODE: number = 2
const SECTION_GOD2ISO: number = 3

@Component
export struct LicensesPage {
  @Prop pagePadding: number = 16
  @Prop contentMaxWidth: number = 840
  @Prop bottomInset: number = 16
  @State expanded: number = -1

  build() {
    Scroll() {
      Column() {
        Column() {
          this.sectionHeader(SECTION_PROJECTS, $r('app.string.licenses_projects'),
            XBIGOD_NAME + ' · ' + ISO2GOD_NAME + ' · ' + GOD2ISO_NAME)
          if (this.expanded === SECTION_PROJECTS) {
            Divider()
              .color($r('app.color.divider'))
            this.projectsSection()
          }

          Divider()
            .color($r('app.color.divider'))
          this.sectionHeader(SECTION_MIT, 'MIT License', $r('app.string.licenses_mit_summary'))
          if (this.expanded === SECTION_MIT) {
            Divider()
              .color($r('app.color.divider'))
            this.mitSection()
          }

          Divider()
            .color($r('app.color.divider'))
          this.sectionHeader(SECTION_UNICODE, 'Unicode License V3', $r('app.string.licenses_unicode_scope'))
          if (this.expanded === SECTION_UNICODE) {
            Divider()
              .color($r('app.color.divider'))
            this.unicodeSection()
          }

          Divider()
            .color($r('app.color.divider'))
          this.sectionHeader(SECTION_GOD2ISO, 'god2iso · CC BY-SA 4.0',
            $r('app.string.licenses_god2iso_summary'))
          if (this.expanded === SECTION_GOD2ISO) {
            Divider()
              .color($r('app.color.divider'))
            this.god2isoSection()
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(15)
        .clip(true)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.contentMaxWidth })
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
  sectionHeader(index: number, title: ResourceStr, subtitle: ResourceStr) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
          .rotate({ angle: this.expanded === index ? 180 : 0 })
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
      this.expanded = this.expanded === index ? -1 : index
    })
  }

  @Builder
  projectsSection() {
    Column({ space: 10 }) {
      Text($r('app.string.licenses_project_self'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      this.projectInfo(XBIGOD_NAME, XBIGOD_COPYRIGHT, XBIGOD_URL)
      Text($r('app.string.licenses_project_upstream'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 4 })
      this.projectInfo(ISO2GOD_NAME, ISO2GOD_COPYRIGHT, ISO2GOD_URL)
      this.projectInfo(GOD2ISO_NAME, GOD2ISO_COPYRIGHT, GOD2ISO_URL)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  projectInfo(name: string, copyright: string, url: string) {
    Column({ space: 2 }) {
      Text(name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(copyright)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text(url)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .padding({ left: 0, right: 0 })
      .backgroundColor(Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.copyUrl(url)
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private async copyUrl(url: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url)
      await pasteboard.getSystemPasteboard().setData(data)
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.licenses_link_copied'),
        duration: 2000
      })
    } catch (_e) {
      // ignore
    }
  }

  @Builder
  mitSection() {
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

  @Builder
  unicodeSection() {
    Column({ space: 10 }) {
      this.textBlock($r('app.string.licenses_copyright_notices'),
        UNICODE_COPYRIGHT + '\n' + 'Rust Standard Library  ·  ' + RUST_STD_UNICODE_COPYRIGHT)
      this.textBlock($r('app.string.licenses_full_text'), UNICODE_LICENSE_TEXT)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  god2isoSection() {
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