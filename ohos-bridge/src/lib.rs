//! XBiGOD 鸿蒙版原生桥接层。
//!
//! 将 iso2god-rs 转换引擎通过 C FFI 导出，供 C++ NAPI 模块调用。
//! 接口设计与 Android 版 android-bridge 等价，但使用 C ABI 而非 JNI。

use libc::{c_char, c_int, dup};
use serde::Serialize;
use std::ffi::CStr;
use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::os::fd::{FromRawFd, IntoRawFd, RawFd};
use std::sync::atomic::{AtomicBool, Ordering};

mod icon;
mod god2iso;

use iso2god_src::executable::TitleInfo;
use iso2god_src::game_list;
use iso2god_src::god;
use iso2god_src::iso::IsoReader;

static CANCEL_FLAG: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Copy)]
#[repr(i32)]
enum ProgressStage {
    WritingParts = 0,
    WritingMht = 1,
    WritingHeader = 2,
}

#[derive(Clone, Copy, Debug)]
enum ErrorCode {
    IsoRead,
    PartCountMismatch,
    WritePart,
    Mht,
    Header,
    NoIcon,
    IconWrite,
    GodHeader,
    GodPart,
    WriteIso,
    Unknown,
}

impl ErrorCode {
    fn as_str(self) -> &'static str {
        match self {
            ErrorCode::IsoRead => "ISO_READ",
            ErrorCode::PartCountMismatch => "PART_COUNT_MISMATCH",
            ErrorCode::WritePart => "WRITE_PART",
            ErrorCode::Mht => "MHT",
            ErrorCode::Header => "HEADER",
            ErrorCode::NoIcon => "NO_ICON",
            ErrorCode::IconWrite => "ICON_WRITE",
            ErrorCode::GodHeader => "GOD_HEADER",
            ErrorCode::GodPart => "GOD_PART",
            ErrorCode::WriteIso => "WRITE_ISO",
            ErrorCode::Unknown => "UNKNOWN",
        }
    }
}

#[derive(Debug)]
struct Failure {
    code: ErrorCode,
    detail: String,
}

impl Failure {
    fn new(code: ErrorCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }

    fn from_error(code: ErrorCode, error: anyhow::Error) -> Self {
        Self {
            code,
            detail: format!("{error:#}"),
        }
    }

    fn to_json(&self) -> String {
        #[derive(Serialize)]
        struct FailureJson<'a> {
            ok: bool,
            code: &'a str,
            detail: &'a str,
        }

        serde_json::to_string(&FailureJson {
            ok: false,
            code: self.code.as_str(),
            detail: &self.detail,
        })
        .unwrap_or_else(|_| r#"{"ok":false,"code":"UNKNOWN","detail":""}"#.to_string())
    }
}

#[derive(Serialize)]
pub struct IsoInfo {
    ok: bool,
    title: String,
    title_id: String,
    media_id: String,
    data_parts: u64,
    data_size: u64,
}

/// 进度回调函数指针类型。
/// current: 当前进度值，total: 总值，stage: 阶段码 (0=写数据包, 1=MHT, 2=头部)
pub type ProgressCallback = extern "C" fn(current: u32, total: u32, stage: i32);

/// 安全地 dup 一个 fd，返回新的 RawFd。调用者负责关闭返回的 fd。
/// 原始 fd 不受影响。
fn safe_dup_fd(fd: RawFd) -> Result<RawFd, String> {
    let new_fd = unsafe { dup(fd) };
    if new_fd < 0 {
        Err(format!("dup({fd}) failed: {}", std::io::Error::last_os_error()))
    } else {
        Ok(new_fd)
    }
}

/// 解析 ISO 元信息。
///
/// # Safety
/// - `out_json` 必须指向有效的可写缓冲区
/// - `out_json_len` 输入为缓冲区大小，输出为实际写入长度（含 null 终止符）
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_get_iso_info(
    iso_fd: c_int,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    let dup_fd = match safe_dup_fd(iso_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::IsoRead, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };

    let file = unsafe { File::from_raw_fd(dup_fd) };

    let info = get_iso_info_internal(&file);

    // File drop 会关闭 dup'd fd，原始 fd 不受影响

    let payload = match info {
        Ok(info) => serde_json::to_string(&info)
            .unwrap_or_else(|e| Failure::new(ErrorCode::Unknown, e.to_string()).to_json()),
        Err(failure) => failure.to_json(),
    };

    write_json_result(&payload, out_json, out_json_len)
}

fn get_iso_info_internal(file: &File) -> Result<IsoInfo, Failure> {
    let file_clone = file
        .try_clone()
        .map_err(|e| Failure::new(ErrorCode::IsoRead, e.to_string()))?;
    let mut source_iso =
        IsoReader::read(file_clone).map_err(|e| Failure::from_error(ErrorCode::IsoRead, e))?;
    let title_info =
        TitleInfo::from_image(&mut source_iso).map_err(|e| Failure::from_error(ErrorCode::IsoRead, e))?;

    let exe_info = title_info.execution_info;
    let title_id = format!("{:08X}", exe_info.title_id);
    let media_id = format!("{:08X}", exe_info.media_id);
    let title = game_list::find_title_by_id(exe_info.title_id).unwrap_or_default();

    let data_size = source_iso.get_max_used_prefix_size();
    let block_count = data_size.div_ceil(god::BLOCK_SIZE);
    let data_parts = block_count.div_ceil(god::BLOCKS_PER_PART);

    Ok(IsoInfo {
        ok: true,
        title,
        title_id,
        media_id,
        data_parts,
        data_size,
    })
}

/// 执行 ISO → GOD 转换。
///
/// # Safety
/// - `part_fds` 必须指向 `part_fds_count` 个有效的 c_int
/// - `out_json` / `out_json_len` 规则同 `xbigod_get_iso_info`
/// - `progress_cb` 必须是有效的函数指针
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_convert_iso(
    iso_fd: c_int,
    header_fd: c_int,
    part_fds: *const c_int,
    part_fds_count: u32,
    progress_cb: ProgressCallback,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    CANCEL_FLAG.store(false, Ordering::SeqCst);

    let iso_dup = match safe_dup_fd(iso_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::IsoRead, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };
    let header_dup = match safe_dup_fd(header_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let _ = unsafe { libc::close(iso_dup) };
            let payload = Failure::new(ErrorCode::Header, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };

    let input_file = unsafe { File::from_raw_fd(iso_dup) };
    let mut header_file = unsafe { File::from_raw_fd(header_dup) };

    let part_fd_slice = unsafe { std::slice::from_raw_parts(part_fds, part_fds_count as usize) };
    let mut part_files: Vec<File> = Vec::with_capacity(part_fds_count as usize);

    for &fd in part_fd_slice {
        match safe_dup_fd(fd) {
            Ok(dup_fd) => part_files.push(unsafe { File::from_raw_fd(dup_fd) }),
            Err(e) => {
                let _ = input_file.into_raw_fd();
                let _ = header_file.into_raw_fd();
                for f in part_files {
                    let _ = f.into_raw_fd();
                }
                let payload = Failure::new(ErrorCode::WritePart, e).to_json();
                return write_json_result(&payload, out_json, out_json_len);
            }
        }
    }

    let mut report_progress = |current: u64, total: u64, stage: ProgressStage| {
        progress_cb(current as u32, total as u32, stage as i32);
    };

    let result = convert_iso_internal(
        &input_file,
        &mut header_file,
        &mut part_files,
        &mut report_progress,
    );

    let _ = input_file.into_raw_fd();
    let _ = header_file.into_raw_fd();
    for file in part_files {
        let _ = file.into_raw_fd();
    }

    let payload = match result {
        Ok(()) => r#"{"ok":true}"#.to_string(),
        Err(failure) => failure.to_json(),
    };
    write_json_result(&payload, out_json, out_json_len)
}

fn convert_iso_internal<F>(
    iso_file: &File,
    header_file: &mut File,
    part_files: &mut [File],
    report_progress: &mut F,
) -> Result<(), Failure>
where
    F: FnMut(u64, u64, ProgressStage),
{
    let iso_file_clone = iso_file
        .try_clone()
        .map_err(|e| Failure::new(ErrorCode::IsoRead, e.to_string()))?;
    let mut source_iso =
        IsoReader::read(iso_file_clone).map_err(|e| Failure::from_error(ErrorCode::IsoRead, e))?;
    let title_info =
        TitleInfo::from_image(&mut source_iso).map_err(|e| Failure::from_error(ErrorCode::IsoRead, e))?;
    let exe_info = title_info.execution_info;
    let content_type = title_info.content_type;

    let data_size = source_iso.get_max_used_prefix_size();
    let block_count = data_size.div_ceil(god::BLOCK_SIZE);
    let part_count = block_count.div_ceil(god::BLOCKS_PER_PART);

    if part_files.len() as u64 != part_count {
        return Err(Failure::new(
            ErrorCode::PartCountMismatch,
            format!("expected {part_count}, got {}", part_files.len()),
        ));
    }

    for (part_index, part_file) in part_files.iter_mut().enumerate() {
        if CANCEL_FLAG.load(Ordering::SeqCst) {
            return Err(Failure::new(ErrorCode::Unknown, "cancelled by user"));
        }

        let part_index = part_index as u64;
        report_progress(part_index, part_count, ProgressStage::WritingParts);

        let mut iso_data_volume = iso_file
            .try_clone()
            .map_err(|e| Failure::new(ErrorCode::WritePart, e.to_string()))?;
        iso_data_volume
            .seek(SeekFrom::Start(source_iso.volume_descriptor.root_offset))
            .map_err(|e| Failure::new(ErrorCode::WritePart, e.to_string()))?;

        god::write_part(iso_data_volume, part_index, part_file)
            .map_err(|e| Failure::from_error(ErrorCode::WritePart, e))?;
    }

    report_progress(part_count, part_count, ProgressStage::WritingMht);

    if part_count > 0 {
        let mut mht = {
            let last_part_file = &mut part_files[(part_count - 1) as usize];
            last_part_file
                .seek(SeekFrom::Start(0))
                .map_err(|e| Failure::new(ErrorCode::Mht, e.to_string()))?;
            god::HashList::read(last_part_file).map_err(|e| Failure::from_error(ErrorCode::Mht, e))?
        };

        for prev_part_index in (0..part_count - 1).rev() {
            if CANCEL_FLAG.load(Ordering::SeqCst) {
                return Err(Failure::new(ErrorCode::Unknown, "cancelled by user"));
            }

            let mut prev_mht = {
                let prev_file = &mut part_files[prev_part_index as usize];
                prev_file
                    .seek(SeekFrom::Start(0))
                    .map_err(|e| Failure::new(ErrorCode::Mht, e.to_string()))?;
                god::HashList::read(prev_file).map_err(|e| Failure::from_error(ErrorCode::Mht, e))?
            };

            prev_mht.add_hash(&mht.digest());

            {
                let prev_file = &mut part_files[prev_part_index as usize];
                prev_file
                    .seek(SeekFrom::Start(0))
                    .map_err(|e| Failure::new(ErrorCode::Mht, e.to_string()))?;
                prev_mht
                    .write(prev_file)
                    .map_err(|e| Failure::from_error(ErrorCode::Mht, e))?;
            }

            mht = prev_mht;
        }

        report_progress(part_count, part_count, ProgressStage::WritingHeader);

        let last_part_size = part_files[(part_count - 1) as usize]
            .metadata()
            .map_err(|e| Failure::new(ErrorCode::Header, e.to_string()))?
            .len();

        let mut con_header_builder = god::ConHeaderBuilder::new()
            .with_execution_info(&exe_info)
            .with_block_counts(block_count as u32, 0)
            .with_data_parts_info(
                part_count as u32,
                last_part_size + (part_count - 1) * god::BLOCK_SIZE * 0xa290,
            )
            .with_content_type(content_type)
            .with_mht_hash(&mht.digest());

        if let Some(game_title) = game_list::find_title_by_id(exe_info.title_id) {
            con_header_builder = con_header_builder.with_game_title(&game_title);
        }

        let con_header = con_header_builder.finalize();
        header_file
            .write_all(&con_header)
            .map_err(|e| Failure::new(ErrorCode::Header, e.to_string()))?;
    }

    Ok(())
}

/// 从 ISO 中提取游戏标题图标并写入 `out_path`。
///
/// # Safety
/// - `out_path` 必须是以 null 结尾的有效 C 字符串
/// - `out_json` / `out_json_len` 规则同 `xbigod_get_iso_info`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_extract_game_icon(
    iso_fd: c_int,
    out_path: *const c_char,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    let path = if out_path.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(out_path) }
            .to_string_lossy()
            .into_owned()
    };
    if path.is_empty() {
        let payload = Failure::new(ErrorCode::IconWrite, "empty icon path").to_json();
        return write_json_result(&payload, out_json, out_json_len);
    }

    let dup_fd = match safe_dup_fd(iso_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::IsoRead, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };
    let file = unsafe { File::from_raw_fd(dup_fd) };

    let payload = match icon::extract_title_icon(&file) {
        Ok(bytes) => match std::fs::write(&path, &bytes) {
            Ok(()) => {
                #[derive(Serialize)]
                struct IconJson {
                    ok: bool,
                    size: usize,
                }
                serde_json::to_string(&IconJson {
                    ok: true,
                    size: bytes.len(),
                })
                .unwrap_or_else(|_| r#"{"ok":true,"size":0}"#.to_string())
            }
            Err(e) => Failure::new(ErrorCode::IconWrite, format!("write {path}: {e}")).to_json(),
        },
        Err(failure) => failure.to_json(),
    };

    write_json_result(&payload, out_json, out_json_len)
}

/// 解析 GOD 包头（`<media_id>` 文件），返回标题与数据包数量。
///
/// # Safety
/// `out_json` / `out_json_len` 规则同 `xbigod_get_iso_info`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_get_god_info(
    header_fd: c_int,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    let dup_fd = match safe_dup_fd(header_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::GodHeader, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };

    let mut header_file = unsafe { File::from_raw_fd(dup_fd) };

    let payload = match god2iso::read_god_info(&mut header_file) {
        Ok(info) => serde_json::to_string(&info)
            .unwrap_or_else(|e| Failure::new(ErrorCode::Unknown, e.to_string()).to_json()),
        Err(failure) => failure.to_json(),
    };

    write_json_result(&payload, out_json, out_json_len)
}

/// 将 GOD 数据包重建为 ISO。
///
/// # Safety
/// - `part_fds` 必须指向 `part_fds_count` 个有效的 c_int
/// - `out_json` / `out_json_len` 规则同 `xbigod_get_iso_info`
/// - `progress_cb` 必须是有效的函数指针
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_convert_god(
    header_fd: c_int,
    part_fds: *const c_int,
    part_fds_count: u32,
    iso_fd: c_int,
    progress_cb: ProgressCallback,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    CANCEL_FLAG.store(false, Ordering::SeqCst);

    let header_dup = match safe_dup_fd(header_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::GodHeader, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };
    let iso_dup = match safe_dup_fd(iso_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let _ = unsafe { libc::close(header_dup) };
            let payload = Failure::new(ErrorCode::WriteIso, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };

    let mut header_file = unsafe { File::from_raw_fd(header_dup) };
    let mut iso_file = unsafe { File::from_raw_fd(iso_dup) };

    let part_fd_slice = unsafe { std::slice::from_raw_parts(part_fds, part_fds_count as usize) };
    let mut part_files: Vec<File> = Vec::with_capacity(part_fds_count as usize);

    for &fd in part_fd_slice {
        match safe_dup_fd(fd) {
            Ok(dup_fd) => part_files.push(unsafe { File::from_raw_fd(dup_fd) }),
            Err(e) => {
                let payload = Failure::new(ErrorCode::GodPart, e).to_json();
                return write_json_result(&payload, out_json, out_json_len);
            }
        }
    }

    let mut report_progress = |current: u64, total: u64, stage: i32| {
        progress_cb(current as u32, total as u32, stage);
    };

    let result = god2iso::convert_god(
        &mut header_file,
        &mut part_files,
        &mut iso_file,
        &mut report_progress,
    );

    let payload = match result {
        Ok(()) => r#"{"ok":true}"#.to_string(),
        Err(failure) => failure.to_json(),
    };
    write_json_result(&payload, out_json, out_json_len)
}

/// 从 GOD 包头中提取嵌入的游戏图标并写入 `out_path`。
///
/// # Safety
/// `out_path` 必须是以 null 结尾的有效 C 字符串；其余同 `xbigod_extract_game_icon`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xbigod_extract_god_icon(
    header_fd: c_int,
    out_path: *const c_char,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    let path = if out_path.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(out_path) }
            .to_string_lossy()
            .into_owned()
    };
    if path.is_empty() {
        let payload = Failure::new(ErrorCode::IconWrite, "empty icon path").to_json();
        return write_json_result(&payload, out_json, out_json_len);
    }

    let dup_fd = match safe_dup_fd(header_fd) {
        Ok(fd) => fd,
        Err(e) => {
            let payload = Failure::new(ErrorCode::GodHeader, e).to_json();
            return write_json_result(&payload, out_json, out_json_len);
        }
    };
    let mut header_file = unsafe { File::from_raw_fd(dup_fd) };

    let payload = match god2iso::read_game_icon(&mut header_file) {
        Ok(bytes) => match std::fs::write(&path, &bytes) {
            Ok(()) => {
                #[derive(Serialize)]
                struct IconJson {
                    ok: bool,
                    size: usize,
                }
                serde_json::to_string(&IconJson {
                    ok: true,
                    size: bytes.len(),
                })
                .unwrap_or_else(|_| r#"{"ok":true,"size":0}"#.to_string())
            }
            Err(e) => Failure::new(ErrorCode::IconWrite, format!("write {path}: {e}")).to_json(),
        },
        Err(failure) => failure.to_json(),
    };

    write_json_result(&payload, out_json, out_json_len)
}

/// 取消正在进行的转换（协作式，在数据包循环和 MHT 循环中检查）。
#[unsafe(no_mangle)]
pub extern "C" fn xbigod_cancel() {
    CANCEL_FLAG.store(true, Ordering::SeqCst);
}

/// 将 JSON 结果写入输出缓冲区。返回 0 表示成功写入。
///
/// # Safety
/// `out_json` 和 `out_json_len` 必须是有效指针。
unsafe fn write_json_result(
    json: &str,
    out_json: *mut c_char,
    out_json_len: *mut u32,
) -> c_int {
    let buf_len = unsafe { *out_json_len } as usize;
    let json_bytes = json.as_bytes();
    let copy_len = json_bytes.len().min(buf_len.saturating_sub(1));

    unsafe {
        std::ptr::copy_nonoverlapping(json_bytes.as_ptr() as *const c_char, out_json, copy_len);
        *out_json.add(copy_len) = 0; // null terminator
        *out_json_len = (copy_len + 1) as u32;
    }

    0
}
