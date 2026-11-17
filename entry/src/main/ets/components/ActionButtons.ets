import { LayoutSpec } from '../common/LayoutSpec'

@Component
export struct ActionButtons {
  onAddIso: () => void = () => {}
  onStartAll: () => void = () => {}
  @Prop canStartAll: boolean = false
  @Prop isConverting: boolean = false
  @Prop isGodMode: boolean = false

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([Color.White])
            .margin({ right: 8 })
          Text(this.isGodMode ? $r('app.string.action_add_god') : $r('app.string.action_add_iso'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
      }
      .layoutWeight(1)
      .height(40)
      .backgroundColor($r('app.color.success_btn'))
      .borderRadius(LayoutSpec.controlRadius())
      .onClick(() => {
        this.onAddIso()
      })

      Button({ type: ButtonType.Normal }) {
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.success_text')])
            .margin({ right: 8 })
          Text($r('app.string.action_start_all'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success_text'))
        }
      }
      .layoutWeight(1)
      .height(40)
      .backgroundColor($r('app.color.success_bg'))
      .borderRadius(LayoutSpec.controlRadius())
      .enabled(this.canStartAll && !this.isConverting)
      .onClick(() => {
        this.onStartAll()
      })
    }
    .width('100%')
  }
}
