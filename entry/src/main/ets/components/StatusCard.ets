import { LayoutSpec } from '../common/LayoutSpec'

@Component
export struct StatusCard {
  @Prop statusText: string = ''
  @Prop isOk: boolean = false
  @Prop isBusy: boolean = false
  @Prop isError: boolean = false

  private icon(): Resource {
    if (this.isError) {
      return $r('sys.symbol.xmark')
    }
    if (this.isOk) {
      return $r('sys.symbol.checkmark_circle_fill')
    }
    return $r('sys.symbol.info_circle')
  }

  private iconColor(): ResourceColor {
    if (this.isError) {
      return $r('app.color.danger_text')
    }
    if (this.isOk) {
      return $r('app.color.success_text')
    }
    if (this.isBusy) {
      return $r('app.color.accent')
    }
    return $r('app.color.text_secondary')
  }

  build() {
    Row({ space: 8 }) {
      SymbolGlyph(this.icon())
        .fontSize(18)
        .fontColor([this.iconColor()])
      Text(this.statusText)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(LayoutSpec.controlRadius())
  }
}
