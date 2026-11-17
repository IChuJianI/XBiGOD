export class IsoInfo {
  ok: boolean = false
  title: string = ''
  titleId: string = ''
  mediaId: string = ''
  dataParts: number = 0
  dataSize: number = 0
  code: string = ''
  detail: string = ''

  get isValid(): boolean {
    return this.ok
  }

  get sizeGb(): string {
    return (this.dataSize / (1024 * 1024 * 1024)).toFixed(2)
  }
}
