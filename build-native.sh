#!/bin/sh
# 构建 libxbigod_core.so 并复制到 DevEco 项目的 cpp/libs 目录。
# 用法: sh build-native.sh

set -e

RUST_BIN="/storage/Users/currentUser/rust-install/rust-1.95.0-aarch64-unknown-linux-ohos/bin"
PROJECT_ROOT="/storage/Users/currentUser/Documents/DevEcoStudioProjects/XBiGOD"
BRIDGE_DIR="$PROJECT_ROOT/ohos-bridge"
DEST_DIR="$PROJECT_ROOT/entry/src/main/cpp/libs/arm64-v8a"

export PATH="$RUST_BIN:$PATH"
export SSL_CERT_FILE="/data/storage/el2/base/files/home/cacert.pem"
export CARGO_NET_GIT_FETCH_WITH_CLI=true

echo "==> 编译 Rust 桥接库 (aarch64-unknown-linux-ohos)..."
cd "$BRIDGE_DIR"
# 必须写入 DT_SONAME：否则链接方 C++ 模块会把构建机绝对路径记进 DT_NEEDED，
# 设备上的动态加载器找不到该路径，napi 模块加载失败。
cargo rustc --release --target aarch64-unknown-linux-ohos -- \
    -C link-arg=-Wl,-soname,libxbigod_core.so

echo "==> 复制 .so 到 $DEST_DIR"
mkdir -p "$DEST_DIR"
cp "$BRIDGE_DIR/target/aarch64-unknown-linux-ohos/release/libxbigod_core.so" "$DEST_DIR/"

echo "==> 完成: $(ls -lh "$DEST_DIR/libxbigod_core.so")"
