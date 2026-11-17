//! Xbox 360 标题图标提取。
//!
//! 从 ISO 的 `default.xex` 中定位标题 GPD 资源（XDBF），只解压图标所需的
//! 资源区间，避免为一张 64×64 图片解压整个可执行映像。

use aes::cipher::block_padding::NoPadding;
use aes::cipher::{BlockModeDecrypt, KeyIvInit};
use iso2god_src::iso::IsoReader;
use lzxd::{Lzxd, WindowSize};
use std::fs::File;
use std::os::unix::fs::FileExt;

use crate::{ErrorCode, Failure};

type Aes128CbcDec = cbc::Decryptor<aes::Aes128>;

const RETAIL_KEY: [u8; 16] = [
    0x20, 0xB1, 0x85, 0xA5, 0x9D, 0x28, 0xFD, 0xC3, 0x40, 0x58, 0x3F, 0xBB, 0x08, 0x96, 0xBF,
    0x91,
];
const DEVKIT_KEY: [u8; 16] = [0u8; 16];

const XEX_HEADER_FIXED: u64 = 0x18;
const XEX_OPTIONAL_HEADER: u32 = 0x2FF;
const XEX_FILE_FORMAT: u32 = 0x3FF;
const XEX_EXECUTION_INFO: u32 = 0x40006;

const XDBF_TITLE_ICON_ID: u64 = 0x8000;
const XDBF_IMAGE_SECTION: u16 = 2;

const MAX_HEADER_BLOB: usize = 1024 * 1024;
const MAX_OPTIONAL_HEADERS: u32 = 4096;
const MAX_RESOURCE_BYTES: u64 = 32 * 1024 * 1024;
const MAX_ICON_BYTES: usize = 8 * 1024 * 1024;
const MAX_XDBF_ENTRIES: u32 = 100_000;
const LZX_CHUNK: usize = 0x8000;
const MAX_LZX_BLOCK: u64 = 16 * 1024 * 1024;

#[derive(Clone, Copy)]
enum Compression {
    None,
    Basic,
    Normal,
}

#[derive(Clone)]
struct BasicBlock {
    data_size: u32,
    zero_size: u32,
}

struct XexMeta {
    data_offset: u64,
    image_size: u64,
    load_address: u32,
    file_key: [u8; 16],
    encryption: u16,
    compression: Compression,
    blocks: Vec<BasicBlock>,
    window_size: u32,
    first_block_size: u32,
    title_id: u32,
    resources: Vec<Resource>,
}

struct Resource {
    name: String,
    address: u32,
    size: u32,
}

struct XexImage<'a> {
    file: &'a File,
    data_offset: u64,
    data_len: u64,
    image_size: u64,
    session_key: Option<[u8; 16]>,
    compression: Compression,
    blocks: Vec<BasicBlock>,
    window_size: u32,
    first_block_size: u32,
}

pub fn extract_title_icon(file: &File) -> Result<Vec<u8>, Failure> {
    let iso = IsoReader::read(
        file.try_clone()
            .map_err(|e| Failure::new(ErrorCode::IsoRead, e.to_string()))?,
    )
    .map_err(|e| Failure::from_error(ErrorCode::IsoRead, e))?;

    let entry = match iso.directory_table.get_entry("default.xex") {
        Some(entry) if !entry.is_directory() => entry,
        _ => return Err(no_icon("no default.xex in this image")),
    };

    let file_len = file
        .metadata()
        .map_err(|e| Failure::new(ErrorCode::IsoRead, e.to_string()))?
        .len();
    let xex_offset = iso
        .volume_descriptor
        .root_offset
        .checked_add(entry.sector as u64 * iso.volume_descriptor.sector_size)
        .ok_or_else(|| no_icon("invalid executable offset"))?;
    let xex_size = entry.size as u64;

    if xex_size < XEX_HEADER_FIXED || xex_offset.saturating_add(xex_size) > file_len {
        return Err(no_icon("truncated default.xex"));
    }

    let meta = parse_xex(file, xex_offset, xex_size)?;
    let image = XexImage::new(file, &meta, xex_offset, xex_size)?;

    for resource in select_candidates(&meta) {
        if resource.size == 0 || resource.size as u64 > MAX_RESOURCE_BYTES {
            continue;
        }
        if resource.address < meta.load_address {
            continue;
        }
        let image_offset = (resource.address - meta.load_address) as u64;
        if image_offset.saturating_add(resource.size as u64) > meta.image_size {
            continue;
        }

        let data = match image.read_range(image_offset, resource.size as usize) {
            Ok(data) => data,
            Err(_) => continue,
        };
        if let Some(icon) = parse_xdbf_icon(&data) {
            return Ok(icon);
        }
    }

    Err(no_icon("no embedded title icon"))
}

fn no_icon(detail: &str) -> Failure {
    Failure::new(ErrorCode::NoIcon, detail)
}

fn select_candidates(meta: &XexMeta) -> Vec<&Resource> {
    let title_name = format!("{:08X}", meta.title_id);

    let preferred: Vec<&Resource> = meta
        .resources
        .iter()
        .filter(|resource| {
            resource.name.eq_ignore_ascii_case(&title_name)
                || resource.name.to_ascii_lowercase().ends_with(".gpd")
                || resource.name.to_ascii_lowercase().contains("xdbf")
        })
        .collect();
    if !preferred.is_empty() {
        return preferred;
    }

    let hex_named: Vec<&Resource> = meta
        .resources
        .iter()
        .filter(|resource| {
            resource.size > 0
                && resource.size as u64 <= MAX_RESOURCE_BYTES
                && is_hex_name(&resource.name)
        })
        .take(8)
        .collect();
    if !hex_named.is_empty() {
        return hex_named;
    }

    meta.resources
        .iter()
        .filter(|resource| {
            resource.size > 0 && resource.size as u64 <= MAX_RESOURCE_BYTES
        })
        .take(8)
        .collect()
}

fn is_hex_name(name: &str) -> bool {
    name.len() == 8 && name.bytes().all(|b| b.is_ascii_hexdigit())
}

fn parse_xex(file: &File, xex_offset: u64, xex_size: u64) -> Result<XexMeta, Failure> {
    let fixed = read_at(file, xex_offset, XEX_HEADER_FIXED as usize)?;
    if &fixed[0..4] != b"XEX2" {
        return Err(no_icon("default.xex is not XEX2"));
    }

    let data_offset = be_u32(&fixed, 0x08).unwrap_or(0) as u64;
    let security_offset = be_u32(&fixed, 0x10).unwrap_or(0) as u64;
    let optional_count = be_u32(&fixed, 0x14).unwrap_or(0);

    if data_offset < XEX_HEADER_FIXED || data_offset >= xex_size || security_offset >= xex_size {
        return Err(no_icon("invalid XEX header offsets"));
    }
    if optional_count > MAX_OPTIONAL_HEADERS {
        return Err(no_icon("too many XEX optional headers"));
    }

    let table = read_at(file, xex_offset + XEX_HEADER_FIXED, optional_count as usize * 8)?;
    let mut format_blob: Option<Vec<u8>> = None;
    let mut resource_blob: Option<Vec<u8>> = None;
    let mut execution_blob: Option<Vec<u8>> = None;

    for index in 0..optional_count as usize {
        let entry = index * 8;
        let key = match be_u32(&table, entry) {
            Some(key) => key,
            None => break,
        };
        let value = match be_u32(&table, entry + 4) {
            Some(value) => value as u64,
            None => break,
        };
        let wanted = key == XEX_OPTIONAL_HEADER
            || key == XEX_FILE_FORMAT
            || key == XEX_EXECUTION_INFO;
        if !wanted {
            continue;
        }

        let blob = if key & 0xFF == 0xFF {
            let prefix = read_at(file, xex_offset + value, 4)?;
            let total = be_u32(&prefix, 0).unwrap_or(0) as usize;
            if total < 8 || total > MAX_HEADER_BLOB {
                continue;
            }
            read_at(file, xex_offset + value, total)?
        } else {
            let len = (key & 0xFF) as usize * 4;
            if len == 0 {
                continue;
            }
            read_at(file, xex_offset + value, len)?
        };

        if key == XEX_OPTIONAL_HEADER {
            resource_blob = Some(blob);
        } else if key == XEX_FILE_FORMAT {
            format_blob = Some(blob);
        } else {
            execution_blob = Some(blob);
        }
    }

    let format = format_blob.ok_or_else(|| no_icon("missing XEX file format"))?;
    let (encryption, compression, blocks, window_size, first_block_size) =
        parse_file_format(&format)?;
    let resources = resource_blob
        .as_deref()
        .map(parse_resources)
        .unwrap_or_default();
    let title_id = execution_blob
        .as_deref()
        .and_then(|blob| be_u32(blob, 12))
        .unwrap_or(0);

    let security = read_at(file, xex_offset + security_offset, 0x160)?;
    let image_size = be_u32(&security, 0x04).unwrap_or(0) as u64;
    let load_address = be_u32(&security, 0x110).unwrap_or(0);
    let mut file_key = [0u8; 16];
    file_key.copy_from_slice(&security[0x150..0x160]);

    if image_size == 0 {
        return Err(no_icon("invalid XEX image size"));
    }

    Ok(XexMeta {
        data_offset,
        image_size,
        load_address,
        file_key,
        encryption,
        compression,
        blocks,
        window_size,
        first_block_size,
        title_id,
        resources,
    })
}

fn parse_file_format(
    blob: &[u8],
) -> Result<(u16, Compression, Vec<BasicBlock>, u32, u32), Failure> {
    if blob.len() < 8 {
        return Err(no_icon("truncated XEX file format"));
    }
    let encryption = be_u16(blob, 4).unwrap_or(0);
    let compression = be_u16(blob, 6).unwrap_or(0);
    if encryption > 1 {
        return Err(no_icon("unsupported XEX encryption"));
    }

    match compression {
        0 => Ok((encryption, Compression::None, Vec::new(), 0, 0)),
        1 => {
            if (blob.len() - 8) % 8 != 0 {
                return Err(no_icon("truncated XEX block table"));
            }
            let mut blocks = Vec::with_capacity((blob.len() - 8) / 8);
            let mut offset = 8;
            while offset + 8 <= blob.len() {
                blocks.push(BasicBlock {
                    data_size: be_u32(blob, offset).unwrap_or(0),
                    zero_size: be_u32(blob, offset + 4).unwrap_or(0),
                });
                offset += 8;
            }
            Ok((encryption, Compression::Basic, blocks, 0, 0))
        }
        2 => {
            if blob.len() < 16 {
                return Err(no_icon("truncated XEX LZX header"));
            }
            Ok((
                encryption,
                Compression::Normal,
                Vec::new(),
                be_u32(blob, 8).unwrap_or(0),
                be_u32(blob, 12).unwrap_or(0),
            ))
        }
        _ => Err(no_icon("unsupported XEX compression")),
    }
}

fn parse_resources(blob: &[u8]) -> Vec<Resource> {
    if blob.len() < 4 {
        return Vec::new();
    }
    let declared = be_u32(blob, 0).unwrap_or(0) as usize;
    let available = blob.len().min(declared);
    if available < 4 {
        return Vec::new();
    }
    let count = (available - 4) / 16;
    let mut resources = Vec::with_capacity(count);
    for index in 0..count {
        let offset = 4 + index * 16;
        let raw_name = &blob[offset..offset + 8];
        let name_end = raw_name.iter().position(|b| *b == 0).unwrap_or(8);
        let name = String::from_utf8_lossy(&raw_name[..name_end]).into_owned();
        resources.push(Resource {
            name,
            address: be_u32(blob, offset + 8).unwrap_or(0),
            size: be_u32(blob, offset + 12).unwrap_or(0),
        });
    }
    resources
}

impl<'a> XexImage<'a> {
    fn new(file: &'a File, meta: &XexMeta, xex_offset: u64, xex_size: u64) -> Result<Self, Failure> {
        let data_offset = meta.data_offset;
        let data_len = xex_size - data_offset;
        let data_base = xex_offset + data_offset;
        let session_key = if meta.encryption == 1 {
            Some(detect_session_key(file, data_base, data_len, meta)?)
        } else {
            None
        };
        Ok(Self {
            file,
            data_offset: data_base,
            data_len,
            image_size: meta.image_size,
            session_key,
            compression: meta.compression,
            blocks: meta.blocks.clone(),
            window_size: meta.window_size,
            first_block_size: meta.first_block_size,
        })
    }

    fn read_range(&self, offset: u64, len: usize) -> Result<Vec<u8>, Failure> {
        if len == 0 {
            return Ok(Vec::new());
        }
        if offset.saturating_add(len as u64) > self.image_size {
            return Err(no_icon("resource outside XEX image"));
        }
        match self.compression {
            Compression::None => self.read_cipher_range(offset, len),
            Compression::Basic => {
                let mut out = vec![0u8; len];
                self.read_basic_range(offset, len, &mut out)?;
                Ok(out)
            }
            Compression::Normal => self.read_normal_range(offset, len),
        }
    }

    fn read_basic_range(&self, offset: u64, len: usize, out: &mut [u8]) -> Result<(), Failure> {
        let end = offset + len as u64;
        let mut out_cursor = 0u64;
        let mut cipher_cursor = 0u64;
        let mut covered = 0u64;

        for block in &self.blocks {
            let data_start = out_cursor;
            let data_size = block.data_size as u64;
            let data_end = data_start + data_size;
            let zero_end = data_end + block.zero_size as u64;

            let copy_start = offset.max(data_start);
            let copy_end = end.min(data_end).min(zero_end);
            if copy_start < copy_end {
                let count = (copy_end - copy_start) as usize;
                let cipher = cipher_cursor + (copy_start - data_start);
                let bytes = self.read_cipher_range(cipher, count)?;
                let destination = (copy_start - offset) as usize;
                out[destination..destination + count].copy_from_slice(&bytes);
            }

            covered = zero_end;
            out_cursor = zero_end;
            cipher_cursor += data_size;
            if zero_end >= end {
                break;
            }
        }

        if covered < end {
            return Err(no_icon("truncated basic-compressed image"));
        }
        Ok(())
    }

    fn read_normal_range(&self, offset: u64, len: usize) -> Result<Vec<u8>, Failure> {
        let end = offset + len as u64;
        let mut result = vec![0u8; len];
        let mut lzx = Lzxd::new(
            window_size(self.window_size).ok_or_else(|| no_icon("invalid LZX window size"))?,
        );

        let mut block_offset = 0u64;
        let mut block_size = self.first_block_size as u64;
        let mut output_pos = 0u64;

        while block_size > 0 && output_pos < end && output_pos < self.image_size {
            if block_size < 24 || block_size > MAX_LZX_BLOCK ||
                block_offset.saturating_add(block_size) > self.data_len {
                return Err(no_icon("truncated LZX block"));
            }
            let block = self.read_cipher_range(block_offset, block_size as usize)?;
            let next_block = be_u32(&block, 0).unwrap_or(0) as u64;
            let payload = &block[24..];

            let mut payload_pos = 0usize;
            while payload_pos + 2 <= payload.len() && output_pos < end {
                let chunk_size =
                    ((payload[payload_pos] as usize) << 8) | payload[payload_pos + 1] as usize;
                payload_pos += 2;
                if chunk_size == 0 {
                    break;
                }
                if payload_pos + chunk_size > payload.len() {
                    return Err(no_icon("truncated LZX chunk"));
                }

                let remaining = (self.image_size - output_pos) as usize;
                let chunk_output = remaining.min(LZX_CHUNK);
                let decoded = lzx
                    .decompress_next(&payload[payload_pos..payload_pos + chunk_size], chunk_output)
                    .map_err(|e| no_icon(&format!("LZX decode failed: {e}")))?;
                let decoded_end = output_pos + decoded.len() as u64;

                let copy_start = offset.max(output_pos);
                let copy_end = end.min(decoded_end);
                if copy_start < copy_end {
                    let source = (copy_start - output_pos) as usize;
                    let destination = (copy_start - offset) as usize;
                    let count = (copy_end - copy_start) as usize;
                    result[destination..destination + count]
                        .copy_from_slice(&decoded[source..source + count]);
                }

                output_pos = decoded_end;
                payload_pos += chunk_size;
            }

            block_offset += block_size;
            block_size = next_block;
        }

        if output_pos < end {
            return Err(no_icon("truncated LZX image"));
        }
        Ok(result)
    }

    fn read_cipher_range(&self, offset: u64, len: usize) -> Result<Vec<u8>, Failure> {
        if offset.saturating_add(len as u64) > self.data_len {
            return Err(no_icon("range outside XEX data"));
        }
        let Some(key) = self.session_key else {
            return read_at(self.file, self.data_offset + offset, len);
        };

        let aligned_start = offset & !0xF;
        let skip = (offset - aligned_start) as usize;
        let needed = skip + len;
        let aligned_len = (needed + 15) & !0xF;
        let available = self.data_len - aligned_start;
        let read_len = aligned_len.min(available as usize);
        if read_len < needed {
            return Err(no_icon("truncated encrypted range"));
        }

        let mut bytes = read_at(
            self.file,
            self.data_offset + aligned_start,
            read_len,
        )?;
        let iv = if aligned_start >= 16 {
            let prefix = read_at(self.file, self.data_offset + aligned_start - 16, 16)?;
            let mut iv = [0u8; 16];
            iv.copy_from_slice(&prefix);
            iv
        } else {
            [0u8; 16]
        };

        let full = bytes.len() & !0xF;
        if full < needed {
            return Err(no_icon("encrypted range is not block aligned"));
        }
        aes_cbc_decrypt(&key, &iv, &mut bytes[..full]);
        Ok(bytes[skip..skip + len].to_vec())
    }
}

fn detect_session_key(
    file: &File,
    data_offset: u64,
    data_len: u64,
    meta: &XexMeta,
) -> Result<[u8; 16], Failure> {
    let test_len = match meta.compression {
        Compression::Normal => 32,
        _ => 16,
    } as u64;
    if data_len < test_len {
        return Err(no_icon("truncated encrypted XEX data"));
    }

    let retail = decrypt_key(&meta.file_key, &RETAIL_KEY);
    let mut probe = read_at(file, data_offset, test_len as usize)?;
    aes_cbc_decrypt(&retail, &[0u8; 16], &mut probe);
    if plausible_probe(&probe, meta, data_len) {
        return Ok(retail);
    }

    let devkit = decrypt_key(&meta.file_key, &DEVKIT_KEY);
    let mut probe = read_at(file, data_offset, test_len as usize)?;
    aes_cbc_decrypt(&devkit, &[0u8; 16], &mut probe);
    if plausible_probe(&probe, meta, data_len) {
        return Ok(devkit);
    }

    Ok(retail)
}

fn plausible_probe(probe: &[u8], meta: &XexMeta, data_len: u64) -> bool {
    match meta.compression {
        Compression::Normal => {
            let next = be_u32(probe, 0).unwrap_or(u32::MAX) as u64;
            (next == 0 || (24..=data_len).contains(&next))
                && (meta.first_block_size as u64) >= 24
                && meta.first_block_size as u64 <= data_len
        }
        _ => probe.len() >= 2 && probe[0] == b'M' && probe[1] == b'Z',
    }
}

fn decrypt_key(file_key: &[u8; 16], master_key: &[u8; 16]) -> [u8; 16] {
    let mut key = *file_key;
    aes_cbc_decrypt(master_key, &[0u8; 16], &mut key);
    key
}

fn aes_cbc_decrypt(key: &[u8; 16], iv: &[u8; 16], data: &mut [u8]) {
    let aligned = data.len() & !0xF;
    if aligned == 0 {
        return;
    }
    Aes128CbcDec::new(key.into(), iv.into())
        .decrypt_padded::<NoPadding>(&mut data[..aligned])
        .expect("AES-CBC decryption requires block-aligned input");
}

fn window_size(value: u32) -> Option<WindowSize> {
    match value {
        0x8000 => Some(WindowSize::KB32),
        0x10000 => Some(WindowSize::KB64),
        0x20000 => Some(WindowSize::KB128),
        0x40000 => Some(WindowSize::KB256),
        0x80000 => Some(WindowSize::KB512),
        0x100000 => Some(WindowSize::MB1),
        0x200000 => Some(WindowSize::MB2),
        _ => None,
    }
}

fn parse_xdbf_icon(data: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 24 || &data[0..4] != b"XDBF" {
        return None;
    }

    let entry_count = be_u32(data, 8)?;
    let entry_used = be_u32(data, 12)?;
    let free_count = be_u32(data, 16)?;
    if entry_count > MAX_XDBF_ENTRIES || free_count > MAX_XDBF_ENTRIES {
        return None;
    }

    let entries_end = 24usize
        .checked_add(entry_count as usize * 18)?;
    let content_offset = entries_end.checked_add(free_count as usize * 8)?;
    if entries_end > data.len() || content_offset > data.len() {
        return None;
    }

    let used = entry_used.min(entry_count) as usize;
    for index in 0..used {
        let entry = 24 + index * 18;
        let section = be_u16(data, entry)?;
        let id = be_u64(data, entry + 2)?;
        if section != XDBF_IMAGE_SECTION || id != XDBF_TITLE_ICON_ID {
            continue;
        }

        let icon_offset = be_u32(data, entry + 10)? as usize;
        let icon_size = be_u32(data, entry + 14)? as usize;
        if icon_size == 0 || icon_size > MAX_ICON_BYTES {
            return None;
        }
        let start = content_offset.checked_add(icon_offset)?;
        let end = start.checked_add(icon_size)?;
        if end > data.len() {
            return None;
        }
        let icon = &data[start..end];
        if is_supported_image(icon) {
            return Some(icon.to_vec());
        }
    }

    None
}

fn is_supported_image(data: &[u8]) -> bool {
    if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        return true;
    }
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return true;
    }
    if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
        return true;
    }
    if data.len() >= 12 && data.starts_with(b"RIFF") && &data[8..12] == b"WEBP" {
        return true;
    }
    data.starts_with(b"BM")
}

fn read_at(file: &File, offset: u64, len: usize) -> Result<Vec<u8>, Failure> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let mut bytes = vec![0u8; len];
    file.read_exact_at(&mut bytes, offset)
        .map_err(|e| Failure::new(ErrorCode::IsoRead, format!("read at {offset:#x}: {e}")))?;
    Ok(bytes)
}

fn be_u16(data: &[u8], offset: usize) -> Option<u16> {
    let bytes = data.get(offset..offset + 2)?;
    Some(u16::from_be_bytes([bytes[0], bytes[1]]))
}

fn be_u32(data: &[u8], offset: usize) -> Option<u32> {
    let bytes = data.get(offset..offset + 4)?;
    Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn be_u64(data: &[u8], offset: usize) -> Option<u64> {
    let bytes = data.get(offset..offset + 8)?;
    Some(u64::from_be_bytes([
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
    ]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_title_icon_from_xdbf() {
        let mut data = Vec::new();
        data.extend_from_slice(b"XDBF");
        data.extend_from_slice(&0x10000u32.to_be_bytes());
        data.extend_from_slice(&1u32.to_be_bytes());
        data.extend_from_slice(&1u32.to_be_bytes());
        data.extend_from_slice(&0u32.to_be_bytes());
        data.extend_from_slice(&0u32.to_be_bytes());
        data.extend_from_slice(&2u16.to_be_bytes());
        data.extend_from_slice(&XDBF_TITLE_ICON_ID.to_be_bytes());
        data.extend_from_slice(&0u32.to_be_bytes());
        data.extend_from_slice(&8u32.to_be_bytes());
        data.extend_from_slice(b"\x89PNG\r\n\x1a\n");

        let icon = parse_xdbf_icon(&data).expect("title icon");
        assert_eq!(icon, b"\x89PNG\r\n\x1a\n");
    }

    #[test]
    fn extracts_icon_from_test_iso() {
        let Ok(path) = std::env::var("XBIGOD_TEST_ISO") else {
            return;
        };
        let file = File::open(path).expect("open test ISO");
        let icon = extract_title_icon(&file).expect("extract icon");
        assert!(is_supported_image(&icon));
        if let Ok(output) = std::env::var("XBIGOD_TEST_ICON_OUT") {
            std::fs::write(output, icon).expect("write icon");
        }
    }
}
