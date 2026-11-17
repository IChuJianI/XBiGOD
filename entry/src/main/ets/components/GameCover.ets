import { common } from '@kit.AbilityKit'

@Component
export struct GameCover {
  @Prop uri: string = ''
  @Prop loading: boolean = false
  @Prop coverSize: number = 64
  @Prop title: string = ''

  private label(res: Resource): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    return context.resourceManager.getStringSync(res.id)
  }

  build() {
    Stack() {
      if (this.uri.length > 0) {
        Image(this.uri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
          .accessibilityText(this.label($r('app.string.game_cover_label')).replace('%s', this.title))
      } else if (this.loading) {
        LoadingProgress()
          .width(this.coverSize * 0.32)
          .height(this.coverSize * 0.32)
          .color($r('app.color.accent'))
          .accessibilityText(this.label($r('app.string.game_cover_loading')))
      } else {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(this.coverSize * 0.34)
          .fontColor([$r('app.color.icon_empty')])
          .accessibilityText(this.label($r('app.string.game_cover_missing')))
      }
    }
    .width(this.coverSize)
    .height(this.coverSize)
    .backgroundColor($r('app.color.surface_secondary'))
    .borderRadius(10)
    .clip(true)
  }
}
