export enum ConversionStage {
  IDLE = 0,
  ANALYZING = 1,
  ANALYZED = 2,
  PREPARING = 3,
  CONVERTING = 4,
  COMPLETED = 5,
  ERROR = 6
}

export enum ProgressStage {
  WRITING_PARTS = 0,
  WRITING_MHT = 1,
  WRITING_HEADER = 2
}

export enum ErrorCode {
  ISO_READ = 'ISO_READ',
  PART_COUNT_MISMATCH = 'PART_COUNT_MISMATCH',
  WRITE_PART = 'WRITE_PART',
  MHT = 'MHT',
  HEADER = 'HEADER',
  UNKNOWN = 'UNKNOWN'
}
