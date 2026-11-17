cmake_minimum_required(VERSION 3.18.1)
project(xbigod_napi)

set(CMAKE_CXX_STANDARD 17)

# 预编译的 Rust 核心库
add_library(xbigod_core SHARED IMPORTED)
set_target_properties(xbigod_core PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libs/${OHOS_ARCH}/libxbigod_core.so
)

# NAPI 桥接模块
add_library(xbigod_napi SHARED
    napi_init.cpp
    napi_iso2god.cpp
)

target_include_directories(xbigod_napi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(xbigod_napi PRIVATE
    libace_napi.z.so
    libhilog_ndk.z.so
    xbigod_core
)

# IMPORTED 库不会被 CMake 复制到输出目录；显式同步，避免打包进去的是旧 .so。
# 必须写入 CMAKE_LIBRARY_OUTPUT_DIRECTORY（hvigor 的打包目录），而不是 .cxx 构建目录。
if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(XBIGOD_CORE_OUTPUT_DIR ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
else()
    set(XBIGOD_CORE_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR})
endif()

add_custom_target(xbigod_core_sync ALL
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/libs/${OHOS_ARCH}/libxbigod_core.so
        ${XBIGOD_CORE_OUTPUT_DIR}/libxbigod_core.so
    COMMENT "Syncing prebuilt libxbigod_core.so"
)
add_dependencies(xbigod_napi xbigod_core_sync)
