import { fileIo } from '@kit.CoreFileKit'

export enum TaskStatus {
  PENDING = 0,
  ANALYZING = 1,
  READY = 2,
  CONVERTING = 3,
  COMPLETED = 4,
  ERROR = 5,
  CANCELLED = 6
}

export enum TaskDirection {
  ISO_TO_GOD = 0,
  GOD_TO_ISO = 1
}

@Observed
export class ConversionTask {
  id: number = 0
  direction: TaskDirection = TaskDirection.ISO_TO_GOD
  isoUri: string = ''
  isoFile: fileIo.File | null = null
  isoFd: number = -1
  godHeaderPath: string = ''
  godDataDirPath: string = ''
  title: string = ''
  titleId: string = ''
  consoleModel: string = ''
  mediaId: string = ''
  dataParts: number = 0
  dataSize: number = 0
  isValid: boolean = false
  status: TaskStatus = TaskStatus.PENDING
  progress: number = 0
  progressMessage: string = ''
  progressResId: number = 0
  progressArgs: (string | number)[] = []
  errorCode: string = ''
  errorDetail: string = ''
  timestamp: number = Date.now()
  iconUri: string = ''
  iconLoading: boolean = false
  iconChecked: boolean = false

  get fileName(): string {
    const slash: number = Math.max(this.isoUri.lastIndexOf('/'), this.isoUri.lastIndexOf('\\'))
    const name: string = this.isoUri.substring(slash + 1)
    return name.length > 0 ? name : this.isoUri
  }

  get displayTitle(): string {
    return this.title.length > 0 ? this.title : this.fileName
  }

  get sizeGb(): string {
    return (this.dataSize / (1024 * 1024 * 1024)).toFixed(2)
  }

  closeFile(): void {
    if (this.isoFile !== null) {
      try {
        fileIo.closeSync(this.isoFile)
      } catch (_e) {
        // ignore
      }
      this.isoFile = null
    }
    this.isoFd = -1
  }
}
