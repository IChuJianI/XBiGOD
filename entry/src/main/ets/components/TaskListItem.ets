import { common } from '@kit.AbilityKit'
import { ConversionTask, TaskStatus } from '../model/ConversionTask'
import { GameCover } from './GameCover'

@Component
export struct TaskListItem {
  @ObjectLink task: ConversionTask
  @Prop canStart: boolean = true
  @Prop unknownTitle: string = 'Unknown'
  @Prop errorText: string = ''
  onStart: () => void = () => {}
  onRemove: () => void = () => {}
  onCancel: () => void = () => {}

  private statusLabel(): Resource {
    switch (this.task.status) {
      case TaskStatus.PENDING:
        return $r('app.string.task_status_pending')
      case TaskStatus.ANALYZING:
        return $r('app.string.task_status_analyzing')
      case TaskStatus.READY:
        return $r('app.string.task_status_ready')
      case TaskStatus.CONVERTING:
        return $r('app.string.task_status_converting')
      case TaskStatus.COMPLETED:
        return $r('app.string.task_status_completed')
      case TaskStatus.ERROR:
        return $r('app.string.task_status_error')
      case TaskStatus.CANCELLED:
        return $r('app.string.task_status_cancelled')
      default:
        return $r('app.string.task_status_pending')
    }
  }

  private statusSymbol(): Resource {
    switch (this.task.status) {
      case TaskStatus.READY:
        return $r('sys.symbol.checkmark_circle')
      case TaskStatus.CONVERTING:
      case TaskStatus.ANALYZING:
        return $r('sys.symbol.arrow_clockwise')
      case TaskStatus.COMPLETED:
        return $r('sys.symbol.checkmark_circle_fill')
      case TaskStatus.ERROR:
        return $r('sys.symbol.exclamationmark_circle')
      case TaskStatus.CANCELLED:
        return $r('sys.symbol.xmark_circle')
      default:
        return $r('sys.symbol.clock')
    }
  }

  private statusColor(): ResourceColor {
    switch (this.task.status) {
      case TaskStatus.READY:
      case TaskStatus.CONVERTING:
      case TaskStatus.ANALYZING:
        return $r('app.color.accent')
      case TaskStatus.COMPLETED:
        return $r('app.color.success_text')
      case TaskStatus.ERROR:
        return $r('app.color.danger_text')
      default:
        return $r('app.color.text_secondary')
    }
  }

  private showProgress(): boolean {
    return this.task.status === TaskStatus.ANALYZING || this.task.status === TaskStatus.CONVERTING
  }

  private canStartTask(): boolean {
    return this.task.isValid &&
      (this.task.status === TaskStatus.READY ||
        this.task.status === TaskStatus.ERROR ||
        this.task.status === TaskStatus.CANCELLED)
  }

  private subtitle(): string {
    const status = this.str(this.statusLabel())
    if (this.task.status === TaskStatus.CONVERTING) {
      return status + ' ' + Math.floor(this.task.progress).toString() + '%'
    }
    return status
  }

  private displayTitle(): string {
    return this.task.displayTitle.length > 0 ? this.task.displayTitle : this.unknownTitle
  }

  private str(res: Resource): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    return context.resourceManager.getStringSync(res.id)
  }

  @Builder
  headerActions() {
    Row({ space: 4 }) {
      if (this.task.status === TaskStatus.CONVERTING) {
        this.iconAction($r('sys.symbol.xmark'), $r('app.color.danger'),
          $r('app.color.danger_bg'), true,
          $r('app.string.action_cancel_task'), (): void => this.onCancel())
      } else {
        if (this.canStartTask()) {
          this.iconAction($r('sys.symbol.play_fill'), $r('app.color.accent'),
            $r('app.color.accent_bg'), this.canStart,
            $r('app.string.action_start_task'), (): void => this.onStart())
        }
        this.iconAction($r('sys.symbol.trash'), $r('app.color.danger'),
          $r('app.color.danger_bg'), true,
          $r('app.string.action_remove_task'), (): void => this.onRemove())
      }
    }
  }

  @Builder
  iconAction(icon: Resource, fg: ResourceColor, bg: ResourceColor, enabled: boolean,
    label: Resource, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([fg])
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(bg)
    .borderRadius(10)
    .opacity(enabled ? 1 : 0.4)
    .enabled(enabled)
    .accessibilityText(this.str(label))
    .hoverEffect(HoverEffect.Highlight)
    .onClick((): void => action())
  }

  @Builder
  infoCell(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .flexShrink(0)
      Text(value.length > 0 ? value : '—')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 6 })
    }
    .layoutWeight(1)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        SymbolGlyph(this.statusSymbol())
          .fontSize(24)
          .fontColor([this.statusColor()])

        Column({ space: 2 }) {
          Text(this.displayTitle())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.headerActions()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showProgress()) {
        Progress({ value: this.task.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color($r('app.color.accent'))
          .backgroundColor($r('app.color.divider'))
          .style({ strokeWidth: 4 })

        if (this.task.progressMessage.length > 0) {
          Text(this.task.progressMessage)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }

      if (this.task.status === TaskStatus.ERROR && this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor($r('app.color.danger_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.task.isValid) {
        Column({ space: 8 }) {
          Divider()
            .strokeWidth(0.5)
            .color($r('app.color.divider'))

          Row({ space: 10 }) {
            GameCover({
              uri: this.task.iconUri,
              loading: this.task.iconLoading,
              coverSize: 48,
              title: this.displayTitle()
            })

            Column({ space: 6 }) {
              Row({ space: 12 }) {
                this.infoCell($r('app.string.label_title_id'), this.task.titleId)
                this.infoCell($r('app.string.label_media_id'), this.task.mediaId)
              }
              .width('100%')

              Row({ space: 12 }) {
                this.infoCell($r('app.string.label_size'), this.task.sizeGb + ' GB')
                this.infoCell($r('app.string.label_data_parts'), this.task.dataParts.toString())
              }
              .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .clip(true)
  }
}
