// 旧版本只支持 Xbox 360，历史记录没有机型字段，读取时按它补齐
const LEGACY_CONSOLE: string = 'Xbox 360'

export enum HistoryKind {
  CONVERT = 0,
  EXTRACT = 1
}

interface HistoryRecordData {
  title: string
  titleId: string
  sizeGb: string
  timestamp: number
  consoleModel?: string
  kind?: number
}

export class HistoryRecord {
  title: string
  titleId: string
  sizeGb: string
  timestamp: number
  consoleModel: string
  kind: HistoryKind

  constructor(title: string = '', titleId: string = '', sizeGb: string = '', timestamp: number = 0,
    consoleModel: string = '', kind: HistoryKind = HistoryKind.CONVERT) {
    this.title = title
    this.titleId = titleId
    this.sizeGb = sizeGb
    this.timestamp = timestamp
    this.consoleModel = consoleModel
    this.kind = kind
  }

  static serialize(records: HistoryRecord[]): string {
    const items: HistoryRecordData[] = []
    for (let i = 0; i < records.length; i++) {
      const r = records[i]
      const item: HistoryRecordData = {
        title: r.title,
        titleId: r.titleId,
        sizeGb: r.sizeGb,
        timestamp: r.timestamp,
        consoleModel: r.consoleModel,
        kind: r.kind
      }
      items.push(item)
    }
    return JSON.stringify(items)
  }

  static deserialize(raw: string): HistoryRecord[] {
    if (raw.length === 0) {
      return []
    }
    try {
      const items = JSON.parse(raw) as HistoryRecordData[]
      if (!Array.isArray(items)) {
        return HistoryRecord.deserializeLegacy(raw)
      }
      const result: HistoryRecord[] = []
      for (let i = 0; i < items.length; i++) {
        const item: HistoryRecordData = items[i]
        if (item === null || typeof item.title !== 'string' || typeof item.titleId !== 'string' ||
          typeof item.sizeGb !== 'string' || typeof item.timestamp !== 'number') {
          continue
        }
        const rec = new HistoryRecord()
        rec.title = item.title
        rec.titleId = item.titleId
        rec.sizeGb = item.sizeGb
        rec.timestamp = item.timestamp
        rec.consoleModel = typeof item.consoleModel === 'string' && item.consoleModel.length > 0
          ? item.consoleModel : LEGACY_CONSOLE
        rec.kind = item.kind === HistoryKind.EXTRACT ? HistoryKind.EXTRACT : HistoryKind.CONVERT
        result.push(rec)
      }
      return result
    } catch (_e) {
      return HistoryRecord.deserializeLegacy(raw)
    }
  }

  private static deserializeLegacy(raw: string): HistoryRecord[] {
    const recordStrs: string[] = raw.split('\u001E')
    const result: HistoryRecord[] = []
    for (let i = 0; i < recordStrs.length; i++) {
      const fields: string[] = recordStrs[i].split('\u001F')
      if (fields.length >= 4) {
        const rec = new HistoryRecord()
        rec.title = fields[0]
        rec.titleId = fields[1]
        rec.sizeGb = fields[2]
        rec.timestamp = parseInt(fields[3])
        rec.consoleModel = LEGACY_CONSOLE
        result.push(rec)
      }
    }
    return result
  }
}
