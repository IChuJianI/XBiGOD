#ifndef XBIGOD_NAPI_ISO2GOD_H
#define XBIGOD_NAPI_ISO2GOD_H

#include <cstdint>
#include <napi/native_api.h>

// Rust FFI 导出声明
extern "C" {
    typedef void (*ProgressCallback)(uint32_t current, uint32_t total, int32_t stage);

    int32_t xbigod_get_iso_info(
        int32_t iso_fd,
        char *out_json,
        uint32_t *out_json_len
    );

    int32_t xbigod_convert_iso(
        int32_t iso_fd,
        int32_t header_fd,
        const int32_t *part_fds,
        uint32_t part_fds_count,
        ProgressCallback progress_cb,
        char *out_json,
        uint32_t *out_json_len
    );

    int32_t xbigod_extract_game_icon(
        int32_t iso_fd,
        const char *out_path,
        char *out_json,
        uint32_t *out_json_len
    );

    int32_t xbigod_get_god_info(
        int32_t header_fd,
        char *out_json,
        uint32_t *out_json_len
    );

    int32_t xbigod_convert_god(
        int32_t header_fd,
        const int32_t *part_fds,
        uint32_t part_fds_count,
        int32_t iso_fd,
        ProgressCallback progress_cb,
        char *out_json,
        uint32_t *out_json_len
    );

    int32_t xbigod_extract_god_icon(
        int32_t header_fd,
        const char *out_path,
        char *out_json,
        uint32_t *out_json_len
    );

    void xbigod_cancel(void);
}

// NAPI 导出注册
napi_value Init(napi_env env, napi_value exports);

#endif // XBIGOD_NAPI_ISO2GOD_H
