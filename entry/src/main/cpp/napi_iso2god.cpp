#include "napi_iso2god.h"
#include <cstring>
#include <thread>
#include <vector>
#include <string>

// ── 消息类型 ─────────────────────────────────────────────

struct ProgressMsg {
    uint32_t current;
    uint32_t total;
    int32_t stage;
};

struct CompletionMsg {
    std::string json;
};

enum MsgType { MSG_PROGRESS = 0, MSG_COMPLETE = 1 };

struct TsfnPayload {
    MsgType type;
    union {
        ProgressMsg progress;
        CompletionMsg *completion;
    };
};

// ── 全局状态（单实例转换） ───────────────────────────────

static napi_threadsafe_function g_tsfn = nullptr;
static napi_deferred g_deferred = nullptr;
static napi_env g_env = nullptr;

// ── Rust 进度回调（C 函数指针，无捕获） ──────────────────

static void RustProgressCb(uint32_t current, uint32_t total, int32_t stage) {
    if (g_tsfn == nullptr) return;

    auto *payload = new TsfnPayload();
    payload->type = MSG_PROGRESS;
    payload->progress.current = current;
    payload->progress.total = total;
    payload->progress.stage = stage;

    napi_call_threadsafe_function(g_tsfn, payload, napi_tsfn_nonblocking);
}

// ── JS 线程回调 ──────────────────────────────────────────

static void CallJs(napi_env env, napi_value js_callback, void *context, void *data) {
    if (env == nullptr) return;

    auto *payload = static_cast<TsfnPayload *>(data);
    if (payload == nullptr) return;

    if (payload->type == MSG_PROGRESS) {
        // 调用 ArkTS onProgress(current, total, stage)
        if (js_callback != nullptr) {
            napi_value args[3];
            napi_create_uint32(env, payload->progress.current, &args[0]);
            napi_create_uint32(env, payload->progress.total, &args[1]);
            napi_create_int32(env, payload->progress.stage, &args[2]);

            napi_value undefined;
            napi_get_undefined(env, &undefined);
            napi_call_function(env, undefined, js_callback, 3, args, nullptr);
        }
        delete payload;

    } else if (payload->type == MSG_COMPLETE) {
        // 解析 JSON 结果并 resolve/reject Promise
        const char *jsonStr = payload->completion->json.c_str();

        napi_value global, jsonObj, parseFn, jsonVal, parsed;
        napi_get_global(env, &global);
        napi_get_named_property(env, global, "JSON", &jsonObj);
        napi_get_named_property(env, jsonObj, "parse", &parseFn);
        napi_create_string_utf8(env, jsonStr, NAPI_AUTO_LENGTH, &jsonVal);
        napi_call_function(env, jsonObj, parseFn, 1, &jsonVal, &parsed);

        // 检查 ok 字段
        napi_value okVal;
        bool ok = false;
        napi_get_named_property(env, parsed, "ok", &okVal);
        napi_get_value_bool(env, okVal, &ok);

        if (ok) {
            napi_resolve_deferred(env, g_deferred, parsed);
        } else {
            napi_reject_deferred(env, g_deferred, parsed);
        }

        delete payload->completion;
        delete payload;

        // 释放 tsfn
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
        g_deferred = nullptr;
        g_env = nullptr;
    }
}

// ── 工作线程 ─────────────────────────────────────────────

static void ConvertWorker(int32_t isoFd, int32_t headerFd, std::vector<int32_t> partFds) {
    char jsonBuf[4096] = {};
    uint32_t jsonLen = sizeof(jsonBuf);

    xbigod_convert_iso(
        isoFd, headerFd,
        partFds.data(), static_cast<uint32_t>(partFds.size()),
        RustProgressCb,
        jsonBuf, &jsonLen
    );

    // 发送完成消息
    auto *payload = new TsfnPayload();
    payload->type = MSG_COMPLETE;
    payload->completion = new CompletionMsg();
    payload->completion->json = std::string(jsonBuf);

    napi_call_threadsafe_function(g_tsfn, payload, napi_tsfn_blocking);
}

// ── NAPI: getIsoInfo(fd: number): object ─────────────────

static napi_value GetIsoInfo(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t fd = 0;
    napi_get_value_int32(env, argv[0], &fd);

    char jsonBuf[4096] = {};
    uint32_t jsonLen = sizeof(jsonBuf);
    int32_t ret = xbigod_get_iso_info(fd, jsonBuf, &jsonLen);

    if (ret != 0) {
        napi_throw_error(env, nullptr, "xbigod_get_iso_info failed");
        return nullptr;
    }

    // JSON.parse
    napi_value global, jsonObj, parseFn, jsonVal, parsed;
    napi_get_global(env, &global);
    napi_get_named_property(env, global, "JSON", &jsonObj);
    napi_get_named_property(env, jsonObj, "parse", &parseFn);
    napi_create_string_utf8(env, jsonBuf, NAPI_AUTO_LENGTH, &jsonVal);
    napi_call_function(env, jsonObj, parseFn, 1, &jsonVal, &parsed);

    return parsed;
}

// ── NAPI: convertIso(isoFd, headerFd, partFds, onProgress): Promise ──

static napi_value ConvertIso(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t isoFd = 0, headerFd = 0;
    napi_get_value_int32(env, argv[0], &isoFd);
    napi_get_value_int32(env, argv[1], &headerFd);

    // 解析 partFds 数组
    uint32_t arrLen = 0;
    napi_get_array_length(env, argv[2], &arrLen);
    std::vector<int32_t> partFds(arrLen);
    for (uint32_t i = 0; i < arrLen; i++) {
        napi_value elem;
        napi_get_element(env, argv[2], i, &elem);
        napi_get_value_int32(env, elem, &partFds[i]);
    }

    // 创建 Promise
    napi_value promise;
    napi_create_promise(env, &g_deferred, &promise);
    g_env = env;

    // 创建 threadsafe function
    napi_value resourceName;
    napi_create_string_utf8(env, "convertIso", NAPI_AUTO_LENGTH, &resourceName);

    napi_status status = napi_create_threadsafe_function(
        env,
        argv[3],              // ArkTS onProgress 回调
        nullptr,              // async_resource
        resourceName,
        0,                    // max_queue_size (unlimited)
        1,                    // initial_thread_count
        nullptr,              // thread_finalize_data
        nullptr,              // thread_finalize_cb
        nullptr,              // context
        CallJs,               // call_js_cb
        &g_tsfn
    );

    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create threadsafe function");
        return nullptr;
    }

    // 启动工作线程
    std::thread worker(ConvertWorker, isoFd, headerFd, std::move(partFds));
    worker.detach();

    return promise;
}

// ── NAPI: convertGod(headerFd, partFds, isoFd, onProgress): Promise ──

static void ConvertGodWorker(int32_t headerFd, std::vector<int32_t> partFds, int32_t isoFd) {
    char jsonBuf[4096] = {};
    uint32_t jsonLen = sizeof(jsonBuf);

    xbigod_convert_god(
        headerFd,
        partFds.data(), static_cast<uint32_t>(partFds.size()),
        isoFd,
        RustProgressCb,
        jsonBuf, &jsonLen
    );

    auto *payload = new TsfnPayload();
    payload->type = MSG_COMPLETE;
    payload->completion = new CompletionMsg();
    payload->completion->json = std::string(jsonBuf);

    napi_call_threadsafe_function(g_tsfn, payload, napi_tsfn_blocking);
}

static napi_value ConvertGod(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 4) {
        napi_throw_type_error(env, nullptr, "convertGod requires (headerFd, partFds, isoFd, onProgress)");
        return nullptr;
    }

    int32_t headerFd = 0, isoFd = 0;
    napi_get_value_int32(env, argv[0], &headerFd);
    napi_get_value_int32(env, argv[2], &isoFd);

    uint32_t arrLen = 0;
    napi_get_array_length(env, argv[1], &arrLen);
    std::vector<int32_t> partFds(arrLen);
    for (uint32_t i = 0; i < arrLen; i++) {
        napi_value elem;
        napi_get_element(env, argv[1], i, &elem);
        napi_get_value_int32(env, elem, &partFds[i]);
    }

    napi_value promise;
    napi_create_promise(env, &g_deferred, &promise);
    g_env = env;

    napi_value resourceName;
    napi_create_string_utf8(env, "convertGod", NAPI_AUTO_LENGTH, &resourceName);

    napi_status status = napi_create_threadsafe_function(
        env,
        argv[3],
        nullptr,
        resourceName,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        CallJs,
        &g_tsfn
    );

    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create threadsafe function");
        return nullptr;
    }

    std::thread worker(ConvertGodWorker, headerFd, std::move(partFds), isoFd);
    worker.detach();

    return promise;
}

// ── NAPI: cancelConversion(): void ───────────────────────

static napi_value CancelConversion(napi_env env, napi_callback_info info) {
    xbigod_cancel();
    return nullptr;
}

// ── NAPI: extractGameIcon(isoFd, outPath): Promise ───────
// 独立的 async work，不与转换共用 g_deferred / g_tsfn。

struct IconWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    int32_t isoFd = -1;
    bool god = false;
    std::string outPath;
    std::string resultJson;
};

static void IconExecute(napi_env env, void *data) {
    auto *ctx = static_cast<IconWork *>(data);
    char jsonBuf[1024] = {};
    uint32_t jsonLen = sizeof(jsonBuf);
    if (ctx->god) {
        xbigod_extract_god_icon(ctx->isoFd, ctx->outPath.c_str(), jsonBuf, &jsonLen);
    } else {
        xbigod_extract_game_icon(ctx->isoFd, ctx->outPath.c_str(), jsonBuf, &jsonLen);
    }
    ctx->resultJson = jsonBuf[0] != '\0'
        ? std::string(jsonBuf)
        : std::string(R"({"ok":false,"code":"UNKNOWN","detail":"empty icon result"})");
}

static napi_value ParseJsonString(napi_env env, const std::string &jsonStr) {
    napi_value global, jsonObj, parseFn, jsonVal, parsed;
    napi_get_global(env, &global);
    napi_get_named_property(env, global, "JSON", &jsonObj);
    napi_get_named_property(env, jsonObj, "parse", &parseFn);
    napi_create_string_utf8(env, jsonStr.c_str(), NAPI_AUTO_LENGTH, &jsonVal);
    napi_call_function(env, jsonObj, parseFn, 1, &jsonVal, &parsed);
    return parsed;
}

// ── NAPI: getGodInfo(headerFd): object ───────────────────

static napi_value GetGodInfo(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "getGodInfo requires (headerFd)");
        return nullptr;
    }

    int32_t fd = 0;
    napi_get_value_int32(env, argv[0], &fd);

    char jsonBuf[4096] = {};
    uint32_t jsonLen = sizeof(jsonBuf);
    int32_t ret = xbigod_get_god_info(fd, jsonBuf, &jsonLen);

    if (ret != 0) {
        napi_throw_error(env, nullptr, "xbigod_get_god_info failed");
        return nullptr;
    }

    return ParseJsonString(env, std::string(jsonBuf));
}

static void IconComplete(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<IconWork *>(data);

    napi_value parsed = ParseJsonString(env, ctx->resultJson);
    if (parsed == nullptr) {
        napi_value message, error;
        napi_create_string_utf8(env, "icon result parse failed", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, ctx->deferred, error);
    } else {
        bool ok = false;
        napi_value okVal;
        napi_get_named_property(env, parsed, "ok", &okVal);
        napi_get_value_bool(env, okVal, &ok);

        if (ok) {
            napi_resolve_deferred(env, ctx->deferred, parsed);
        } else {
            napi_reject_deferred(env, ctx->deferred, parsed);
        }
    }

    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

static napi_value ExtractIcon(napi_env env, napi_callback_info info, bool god) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_type_error(env, nullptr, "extractIcon requires (fd, outPath)");
        return nullptr;
    }

    auto *ctx = new IconWork();
    ctx->god = god;
    napi_get_value_int32(env, argv[0], &ctx->isoFd);

    size_t pathLen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &pathLen);
    ctx->outPath.resize(pathLen + 1);
    napi_get_value_string_utf8(env, argv[1], &ctx->outPath[0], pathLen + 1, &pathLen);
    ctx->outPath.resize(pathLen);

    napi_value promise;
    napi_create_promise(env, &ctx->deferred, &promise);

    napi_value resourceName;
    napi_create_string_utf8(env, god ? "extractGodIcon" : "extractGameIcon", NAPI_AUTO_LENGTH,
        &resourceName);

    napi_status status = napi_create_async_work(
        env, nullptr, resourceName, IconExecute, IconComplete, ctx, &ctx->work);

    if (status != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create icon async work");
        return nullptr;
    }

    status = napi_queue_async_work(env, ctx->work);
    if (status != napi_ok) {
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to queue icon async work");
        return nullptr;
    }

    return promise;
}

static napi_value ExtractGameIcon(napi_env env, napi_callback_info info) {
    return ExtractIcon(env, info, false);
}

static napi_value ExtractGodIcon(napi_env env, napi_callback_info info) {
    return ExtractIcon(env, info, true);
}

// ── 模块注册 ─────────────────────────────────────────────

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"getIsoInfo", nullptr, GetIsoInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"convertIso", nullptr, ConvertIso, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelConversion", nullptr, CancelConversion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"extractGameIcon", nullptr, ExtractGameIcon, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getGodInfo", nullptr, GetGodInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"convertGod", nullptr, ConvertGod, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"extractGodIcon", nullptr, ExtractGodIcon, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
