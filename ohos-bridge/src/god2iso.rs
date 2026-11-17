//! GOD → ISO 反向转换。
//!
//! 从 GOD 容器的数据包重建 ISO：每个子块的哈希表被跳过，仅复制数据区；
//! 若首个数据块不以 XSF 开头，则补回 64 KiB 的 XSF 头并回填长度与扇区数；
//! 需要时修正目录表里的扇区偏移。
//!
//! 算法参考 god2iso（Copyright (c) 2010-2021 richardaburton@gmail.com，
//! CC BY-SA 4.0），此处为 Rust 独立实现。

use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::sync::atomic::Ordering;

use serde::Serialize;

use crate::{CANCEL_FLAG, ErrorCode, Failure};

const HEADER_FIELDS_LEN: usize = 0x400;
const TITLE_OFFSET: usize = 0x411;
const TITLE_LIMIT: usize = 0x1691;
const SUBPART_DATA_LEN: usize = 0xcc000;
const SUBPART_HASH_LEN: usize = 0x1000;
const XSF_HEADER_LEN: u64 = 0x10000;
const VOLUME_MAGIC: &[u8; 20] = b"MICROSOFT*XBOX*MEDIA";

const PROGRESS_WRITING_PARTS: i32 = 0;
const PROGRESS_WRITING_HEADER: i32 = 1;
const PROGRESS_FIXING_OFFSETS: i32 = 2;

#[derive(Serialize)]
pub struct GodInfo {
    ok: bool,
    title: String,
    title_id: String,
    media_id: String,
    data_parts: u32,
    data_size: u64,
}

fn read_up_to<R: Read>(reader: &mut R, buffer: &mut [u8]) -> std::io::Result<usize> {
    let mut filled = 0;
    while filled < buffer.len() {
        let read = reader.read(&mut buffer[filled..])?;
        if read == 0 {
            break;
        }
        filled += read;
    }
    Ok(filled)
}

fn io_failure(code: ErrorCode, error: std::io::Error) -> Failure {
    Failure::new(code, error.to_string())
}

fn is_god_header(buffer: &[u8]) -> bool {
    if buffer.len() >= 4 && &buffer[0..4] == b"LIVE" {
        return true;
    }
    buffer.len() >= 21 && &buffer[0..21] == b"MICROSOFT*XBOX*MEDIA"
}

fn decode_utf16_be(bytes: &[u8]) -> String {
    let mut units: Vec<u16> = Vec::new();
    let mut index = 0;
    while index + 1 < bytes.len() {
        let unit = u16::from_be_bytes([bytes[index], bytes[index + 1]]);
        if unit == 0 {
            break;
        }
        units.push(unit);
        index += 2;
    }
    String::from_utf16_lossy(&units).trim().to_string()
}

pub fn read_god_info(header: &mut File) -> Result<GodInfo, Failure> {
    let mut buffer = vec![0u8; TITLE_LIMIT];
    header
        .seek(SeekFrom::Start(0))
        .map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    let read = read_up_to(header, &mut buffer).map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    if read < 0x3a8 {
        return Err(Failure::new(ErrorCode::GodHeader, "header is too short"));
    }
    let buffer = &buffer[..read];
    if !is_god_header(buffer) {
        return Err(Failure::new(ErrorCode::GodHeader, "unrecognized GOD header"));
    }

    let media_id = u32::from_be_bytes([buffer[0x354], buffer[0x355], buffer[0x356], buffer[0x357]]);
    let title_id = u32::from_be_bytes([buffer[0x360], buffer[0x361], buffer[0x362], buffer[0x363]]);
    let data_parts = u32::from_le_bytes([buffer[0x3a0], buffer[0x3a1], buffer[0x3a2], buffer[0x3a3]]);
    let parts_size = u32::from_be_bytes([buffer[0x3a4], buffer[0x3a5], buffer[0x3a6], buffer[0x3a7]]);
    if data_parts == 0 {
        return Err(Failure::new(ErrorCode::GodHeader, "missing part count"));
    }

    let title_end = buffer.len().min(TITLE_LIMIT);
    let title = decode_utf16_be(&buffer[TITLE_OFFSET..title_end]);

    Ok(GodInfo {
        ok: true,
        title,
        title_id: format!("{:08X}", title_id),
        media_id: format!("{:08X}", media_id),
        data_parts,
        data_size: parts_size as u64 * 0x100,
    })
}

pub fn read_game_icon(header: &mut File) -> Result<Vec<u8>, Failure> {
    let mut head = [0u8; 0x171a];
    header
        .seek(SeekFrom::Start(0))
        .map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    let read = read_up_to(header, &mut head).map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    if read < 0x1716 {
        return Err(Failure::new(ErrorCode::NoIcon, "no embedded icon"));
    }
    let length = u32::from_be_bytes([head[0x1712], head[0x1713], head[0x1714], head[0x1715]]) as usize;
    if length == 0 || length > 0x400 {
        return Err(Failure::new(ErrorCode::NoIcon, "no embedded icon"));
    }

    let mut icon = vec![0u8; length];
    header
        .seek(SeekFrom::Start(0x171a))
        .map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    let read = read_up_to(header, &mut icon).map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    if read < length || !icon.starts_with(b"\x89PNG") {
        return Err(Failure::new(ErrorCode::NoIcon, "invalid embedded icon"));
    }
    Ok(icon)
}

pub fn convert_god<F>(
    header: &mut File,
    parts: &mut [File],
    iso: &mut File,
    report: &mut F,
) -> Result<(), Failure>
where
    F: FnMut(u64, u64, i32),
{
    if parts.is_empty() {
        return Err(Failure::new(ErrorCode::GodPart, "no data parts"));
    }

    let mut header_bytes = [0u8; HEADER_FIELDS_LEN];
    header
        .seek(SeekFrom::Start(0))
        .map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    let header_read = read_up_to(header, &mut header_bytes)
        .map_err(|e| io_failure(ErrorCode::GodHeader, e))?;
    if header_read < 0x399 || !is_god_header(&header_bytes) {
        return Err(Failure::new(ErrorCode::GodHeader, "unrecognized GOD header"));
    }

    let offset_flag = header_bytes[0x391] & 0x40 != 0;
    let offset_blocks = i32::from_le_bytes([
        header_bytes[0x395],
        header_bytes[0x396],
        header_bytes[0x397],
        header_bytes[0x398],
    ]);

    let mut head = vec![0u8; VOLUME_MAGIC.len() + XSF_HEADER_LEN as usize];
    parts[0]
        .seek(SeekFrom::Start(0x2000))
        .map_err(|e| io_failure(ErrorCode::GodPart, e))?;
    let head_read =
        read_up_to(&mut parts[0], &mut head).map_err(|e| io_failure(ErrorCode::GodPart, e))?;
    let head = &head[..head_read];
    let has_xsf = head.len() >= 3 && &head[..3] == b"XSF";

    let mut iso_len: u64 = 0;
    let mut skip_prefix: u64 = 0;
    if !has_xsf {
        // XGD 数据可能从游戏分区第 0 扇区开始（卷描述符位于数据内 0x10000），
        // 也可能直接从卷描述符开始。按魔数实际位置丢弃与 XSF 头等长的前缀，
        // 保证 "MICROSOFT*XBOX*MEDIA" 落在镜像 0x10000 处，否则 iso2god 判定无效。
        skip_prefix = if head.len() >= XSF_HEADER_LEN as usize + VOLUME_MAGIC.len()
            && &head[XSF_HEADER_LEN as usize..XSF_HEADER_LEN as usize + VOLUME_MAGIC.len()]
                == VOLUME_MAGIC
        {
            XSF_HEADER_LEN
        } else if head.len() >= VOLUME_MAGIC.len() && &head[..VOLUME_MAGIC.len()] == VOLUME_MAGIC {
            0
        } else {
            XSF_HEADER_LEN
        };

        iso.write_all(&build_xsf_header())
            .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
        iso_len += XSF_HEADER_LEN;
    }

    let total_parts = parts.len() as u64;
    let mut data_buffer = vec![0u8; SUBPART_DATA_LEN];
    let mut hash_buffer = vec![0u8; SUBPART_HASH_LEN];

    for (index, part) in parts.iter_mut().enumerate() {
        if CANCEL_FLAG.load(Ordering::SeqCst) {
            return Err(Failure::new(ErrorCode::Unknown, "cancelled by user"));
        }
        report(index as u64, total_parts, PROGRESS_WRITING_PARTS);
        part.seek(SeekFrom::Start(0x2000))
            .map_err(|e| io_failure(ErrorCode::GodPart, e))?;
        loop {
            if CANCEL_FLAG.load(Ordering::SeqCst) {
                return Err(Failure::new(ErrorCode::Unknown, "cancelled by user"));
            }
            let read =
                read_up_to(part, &mut data_buffer).map_err(|e| io_failure(ErrorCode::GodPart, e))?;
            if read == 0 {
                break;
            }
            let mut start = 0usize;
            if skip_prefix > 0 {
                start = skip_prefix.min(read as u64) as usize;
                skip_prefix -= start as u64;
            }
            if start < read {
                iso.write_all(&data_buffer[start..read])
                    .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
                iso_len += (read - start) as u64;
            }
            if read < SUBPART_DATA_LEN {
                break;
            }
            let skipped = read_up_to(part, &mut hash_buffer)
                .map_err(|e| io_failure(ErrorCode::GodPart, e))?;
            if skipped < SUBPART_HASH_LEN {
                break;
            }
        }
    }

    if !has_xsf {
        report(total_parts, total_parts, PROGRESS_WRITING_HEADER);
        write_xsf_fields(iso, iso_len)?;

        if offset_flag && offset_blocks != 0 {
            report(total_parts, total_parts, PROGRESS_FIXING_OFFSETS);
            let offset_sectors = offset_blocks as i64 * 2 - 34;
            fix_sector_offsets(iso, offset_sectors as i32)?;
        }
    }

    iso.set_len(iso_len)
        .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
    iso.flush().map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
    Ok(())
}

fn write_xsf_fields(iso: &mut File, iso_len: u64) -> Result<(), Failure> {
    let length = iso_len as i64 - 0x400;
    iso.seek(SeekFrom::Start(0x8))
        .and_then(|_| iso.write_all(&length.to_le_bytes()))
        .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;

    let sectors = (iso_len / 2048) as u32;
    iso.seek(SeekFrom::Start(0x8050))
        .and_then(|_| iso.write_all(&sectors.to_le_bytes()))
        .and_then(|_| iso.write_all(&sectors.to_be_bytes()))
        .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;

    iso.seek(SeekFrom::Start(0x7a69))
        .and_then(|_| iso.write_all(b"XBiGOD"))
        .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
    Ok(())
}

fn fix_sector_offsets(iso: &mut File, offset: i32) -> Result<(), Failure> {
    let mut directories: Vec<(i64, i64)> = Vec::new();

    iso.seek(SeekFrom::Start(0x10014))
        .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
    let mut field = [0u8; 4];
    let read = read_up_to(iso, &mut field).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
    if read < 4 {
        return Ok(());
    }
    let mut sector = i32::from_le_bytes(field);
    if sector > 0 {
        sector -= offset;
        iso.seek(SeekFrom::Start(0x10014))
            .and_then(|_| iso.write_all(&sector.to_le_bytes()))
            .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
        let read = read_up_to(iso, &mut field).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
        if read < 4 {
            return Ok(());
        }
        let size = i32::from_le_bytes(field);
        directories.push((sector as i64 * 2048, size as i64));
    }

    let mut processed: u32 = 0;
    while let Some((start, length)) = directories.pop() {
        processed += 1;
        if processed > 0x10000 {
            break;
        }
        let end = start + length;
        let mut position = start;

        while position + 4 < end {
            if (position + 4) / 2048 > position / 2048 {
                position += 2048 - (position % 2048);
            }

            iso.seek(SeekFrom::Start(position as u64))
                .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            let read =
                read_up_to(iso, &mut field).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            if read < 4 {
                break;
            }
            if field == [0xff, 0xff, 0xff, 0xff] {
                if end - position > 2048 {
                    position += 2048 - (position % 2048);
                    continue;
                }
                break;
            }

            let read =
                read_up_to(iso, &mut field).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            if read < 4 {
                break;
            }
            let mut entry_sector = i32::from_le_bytes(field);
            if entry_sector > 0 {
                entry_sector -= offset;
                iso.seek(SeekFrom::Start(position as u64 + 4))
                    .and_then(|_| iso.write_all(&entry_sector.to_le_bytes()))
                    .map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            }

            let read =
                read_up_to(iso, &mut field).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            if read < 4 {
                break;
            }
            let size = i32::from_le_bytes(field);

            let mut attr = [0u8; 1];
            let read =
                read_up_to(iso, &mut attr).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            if read < 1 {
                break;
            }

            let mut name_len = [0u8; 1];
            let read =
                read_up_to(iso, &mut name_len).map_err(|e| io_failure(ErrorCode::WriteIso, e))?;
            if read < 1 {
                break;
            }

            let name_len = name_len[0] as i64;
            position += 14 + name_len;
            let remainder = (14 + name_len) % 4;
            if remainder > 0 {
                position += 4 - remainder;
            }

            if attr[0] & 0x10 != 0 {
                directories.push((entry_sector as i64 * 2048, size as i64));
            }
        }
    }

    Ok(())
}

fn build_xsf_header() -> Vec<u8> {
    let mut header = vec![0u8; XSF_HEADER_LEN as usize];
    header[0x0..0x4].copy_from_slice(b"XSF\x1a");
    header[0x5] = 0x04;
    // 长度字段在写入全部数据后回填，这里先放与原头一致的占位。
    header[0x8..0x11].copy_from_slice(b"SIZE-64L\x02");
    header[0x7a69..0x7a6f].copy_from_slice(b"XBiGOD");
    header[0x8000..0x8007].copy_from_slice(b"\x01CD001\x01");
    header[0x8050..0x8058].copy_from_slice(b"SecLSecB");
    header[0x8078] = 0x01;
    header[0x807b] = 0x01;
    header[0x807c] = 0x01;
    header[0x807f] = 0x01;
    header[0x8081] = 0x08;
    header[0x8082] = 0x08;
    for byte in header[0x80be..0x832d].iter_mut() {
        *byte = b' ';
    }
    header[0x832d..0x8371].copy_from_slice(&[b'0'; 0x44]);
    header[0x833d] = 0x00;
    header[0x834e] = 0x00;
    header[0x835f] = 0x00;
    header[0x8370] = 0x00;
    header[0x8371] = 0x01;
    header[0x8800..0x8807].copy_from_slice(b"\xffCD001\x01");
    header
}
