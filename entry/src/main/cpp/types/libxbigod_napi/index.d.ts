export interface IsoInfoResult {
    ok: boolean;
    title: string;
    title_id: string;
    media_id: string;
    data_parts: number;
    data_size: number;
    code?: string;
    detail?: string;
}

export interface ConvertResult {
    ok: boolean;
    code?: string;
    detail?: string;
}

export interface IconResult {
    ok: boolean;
    size: number;
    code?: string;
    detail?: string;
}

export interface GodInfoResult {
    ok: boolean;
    title: string;
    title_id: string;
    media_id: string;
    data_parts: number;
    data_size: number;
    code?: string;
    detail?: string;
}

export function getIsoInfo(fd: number): IsoInfoResult;

export function getGodInfo(headerFd: number): GodInfoResult;

export function extractGameIcon(isoFd: number, outPath: string): Promise<IconResult>;

export function extractGodIcon(headerFd: number, outPath: string): Promise<IconResult>;

export function convertIso(
    isoFd: number,
    headerFd: number,
    partFds: number[],
    onProgress: (current: number, total: number, stage: number) => void
): Promise<ConvertResult>;

export function convertGod(
    headerFd: number,
    partFds: number[],
    isoFd: number,
    onProgress: (current: number, total: number, stage: number) => void
): Promise<ConvertResult>;

export function cancelConversion(): void;
