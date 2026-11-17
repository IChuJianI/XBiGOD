import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HistoryRecord } from './HistoryRecord'

const PREF_NAME: string = 'conversion_history'
const HISTORY_KEY: string = 'history_records'
const MAX_RECORDS: number = 50
const DOMAIN: number = 0x0000

export class HistoryStore {
  private records: HistoryRecord[] = []
  private prefs: preferences.Preferences | undefined = undefined

  init(context: common.UIAbilityContext): void {
    try {
      const opts: preferences.Options = { name: PREF_NAME }
      this.prefs = preferences.getPreferencesSync(context, opts)
      const stored = this.prefs.getSync(HISTORY_KEY, '')
      const raw: string = typeof stored === 'string' ? stored : ''
      this.records = HistoryRecord.deserialize(raw)
    } catch (err) {
      this.prefs = undefined
      this.records = []
      hilog.error(DOMAIN, 'XBiGOD', 'Failed to load history: %{public}s', (err as Error).message)
    }
  }

  getAll(): HistoryRecord[] {
    return this.records
  }

  add(record: HistoryRecord): void {
    this.records.unshift(record)
    if (this.records.length > MAX_RECORDS) {
      this.records = this.records.slice(0, MAX_RECORDS)
    }
    this.save()
  }

  removeAt(index: number): void {
    if (index >= 0 && index < this.records.length) {
      this.records.splice(index, 1)
      this.save()
    }
  }

  clear(): void {
    this.records = []
    this.save()
  }

  private save(): void {
    if (this.prefs === undefined) {
      return
    }
    try {
      this.prefs.putSync(HISTORY_KEY, HistoryRecord.serialize(this.records))
      this.prefs.flushSync()
    } catch (err) {
      hilog.error(DOMAIN, 'XBiGOD', 'Failed to save history: %{public}s', (err as Error).message)
    }
  }
}
