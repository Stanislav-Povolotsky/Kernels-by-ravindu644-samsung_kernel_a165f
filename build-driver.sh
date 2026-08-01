#!/bin/bash
# Copyright (c) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Standalone driver build script for SM-A165F.
#
# Builds a single in-tree driver as an out-of-tree (external) kernel module
# (.ko) against the device kernel, WITHOUT compiling the full kernel/boot
# image. It reuses the exact toolchain and defconfig machinery of ./build.sh:
#   1. downloads Samsung's NDK toolchain (same as build.sh),
#   2. generates the build.config via gen_build_config.py,
#   3. overrides MAKE_GOALS to "modules_prepare" (so only the kernel is
#      *prepared*, not fully built) and points EXT_MODULES at the driver,
#   4. lets kernel/build/build.sh prepare the tree and compile the module.
#
# NOTE: the module is compiled against a *prepared* (not fully built) kernel.
# If out/.../KERNEL_OBJ already contains a full ./build.sh output (with a
# populated Module.symvers) the module links cleanly against it. Otherwise
# modpost may print harmless "undefined symbol" warnings; the .ko is still
# produced and is fine for a compile check / development loading.
#
# By default this builds drivers/input/touchscreen/ZT7650M -> zt7650m.ko.
# Point DRIVER_REL_PATH at any other in-tree driver directory to reuse it.

set -euo pipefail

SCRIPT_DIR="$(dirname $(readlink -fq "$0"))"
cd "${SCRIPT_DIR}"

# --- driver to build (path relative to the kernel source root, kernel-5.10) ---
DRIVER_REL_PATH="${DRIVER_REL_PATH:-drivers/input/touchscreen/ZT7650M}"
DRIVER_NAME="$(basename "${DRIVER_REL_PATH}")"

if [[ ! -d "${SCRIPT_DIR}/kernel-5.10/${DRIVER_REL_PATH}" ]]; then
    echo "ERROR: driver directory not found: kernel-5.10/${DRIVER_REL_PATH}" >&2
    exit 1
fi

KERNEL_VERSION="$(cd kernel-5.10 && make kernelversion 2>/dev/null)"

# init & update git submodules
git submodule update --init --recursive

# download & install Samsung's ndk (identical to build.sh)
if [[ ! -d "${SCRIPT_DIR}/kernel/prebuilts" || ! -d "${SCRIPT_DIR}/prebuilts" ]]; then
    echo -e "Cloning Samsung's NDK..."
        curl -LO "https://github.com/Kernels-by-ravindu644/samsung_kernel_a165f/releases/download/toolchain/toolchain.tar.gz" || {
        echo "Failed to download Samsung's NDK. Please check your internet connection and try again." && exit 1
    }
    tar -xf toolchain.tar.gz && rm toolchain.tar.gz
fi

# keep any existing kernel build output (a full ./build.sh output gives a
# populated Module.symvers -> cleaner module linking); only reset dist.
KERNEL_OBJ="${SCRIPT_DIR}/out/target/product/a16/obj/KERNEL_OBJ"
rm -rf "${SCRIPT_DIR}/dist" && mkdir -p "${SCRIPT_DIR}/dist" "${KERNEL_OBJ}"

# generate the build.config (same invocation as build.sh)
cd "${SCRIPT_DIR}/kernel-5.10" && \
    python scripts/gen_build_config.py \
        --kernel-defconfig a16_00_defconfig \
        --kernel-defconfig-overlays entry_level.config \
        -m user \
        -o "${KERNEL_OBJ}/build.config" && \
        cd "${SCRIPT_DIR}"

# Override the generated config so we only PREPARE the kernel and build the
# external module. build.config.mtk is the last-sourced fragment, so lines
# appended here win over the values written by gen_build_config.py.
#   MAKE_GOALS=modules_prepare -> skip vmlinux/Image/full modules build
#   EXT_MODULES=<driver>       -> build.sh's external-module loop builds our .ko
#   IN_KERNEL_MODULES=         -> don't try to modules_install unbuilt in-tree modules
#   FILES=                     -> nothing to copy into DIST_DIR (no vmlinux)
cat >> "${KERNEL_OBJ}/build.config.mtk" <<EOF

# --- appended by build-driver.sh (single external module build) ---
MAKE_GOALS="modules_prepare"
EXT_MODULES="kernel-5.10/${DRIVER_REL_PATH}"
IN_KERNEL_MODULES=
FILES=
EOF

# environment variables (mirrors build.sh)
export ARCH=arm64
export PLATFORM_VERSION=13
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export OUT_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
export DIST_DIR="../out/target/product/a16/obj/KERNEL_OBJ"
export BUILD_CONFIG="../out/target/product/a16/obj/KERNEL_OBJ/build.config"

# custom defconfigs support (identical to build.sh, so the module is compiled
# against the same .config the real kernel uses)
export MERGE_CONFIG="${SCRIPT_DIR}/kernel-5.10/scripts/kconfig/merge_config.sh"
if [ -d "${SCRIPT_DIR}/custom_defconfigs" ]; then
    CUSTOM_DEFCONFIGS_LIST=$(find "${SCRIPT_DIR}/custom_defconfigs" -maxdepth 1 -type f -exec realpath {} \; | tr '\n' ' ')
else
    CUSTOM_DEFCONFIGS_LIST=""
fi
export CUSTOM_DEFCONFIGS_LIST

export MAKE_MENUCONFIG=0

# minimal build options: prepare + external module only, no boot image
GKI_KERNEL_BUILD_OPTIONS=(
    "LTO=thin"
    "SKIP_MRPROPER=1"
    "KMI_SYMBOL_LIST_STRICT_MODE=0"
    "ABI_DEFINITION="
    "SKIP_CP_KERNEL_HDR=1"
)

build_driver() {
    cd "${SCRIPT_DIR}/kernel"
    env "${GKI_KERNEL_BUILD_OPTIONS[@]}" ./build/build.sh
    cd "${SCRIPT_DIR}"
}

collect_module() {
    echo "========================================================"
    echo " Collecting ${DRIVER_NAME} module(s)"
    local found=0

    # Prefer the copy that modules_install placed in the staging dir: it was
    # installed with INSTALL_MOD_STRIP=1, i.e. already stripped of the
    # CONFIG_DEBUG_INFO debug data (the unstripped build output is several
    # times larger). Staging only holds our external module(s).
    if [ -d "${KERNEL_OBJ}/staging" ]; then
        while IFS= read -r ko; do
            cp -v "${ko}" "${SCRIPT_DIR}/dist/"
            found=1
        done < <(find "${KERNEL_OBJ}/staging" -type f -name '*.ko')
    fi

    # Fall back to the freshly built (unstripped) module and strip it ourselves.
    if [ "${found}" -eq 0 ]; then
        local strip_bin
        strip_bin="$(find "${SCRIPT_DIR}/kernel/prebuilts" "${SCRIPT_DIR}/prebuilts" \
            -type f -name 'llvm-strip' 2>/dev/null | head -n1)"
        while IFS= read -r ko; do
            local dst="${SCRIPT_DIR}/dist/$(basename "${ko}")"
            cp -v "${ko}" "${dst}"
            if [ -n "${strip_bin}" ]; then
                "${strip_bin}" --strip-debug "${dst}"
            else
                echo "WARNING: llvm-strip not found; ${dst##*/} keeps debug info (large)" >&2
            fi
            found=1
        done < <(find "${KERNEL_OBJ}" -type f -name '*.ko' -path "*${DRIVER_REL_PATH}*")
    fi

    if [ "${found}" -eq 0 ]; then
        echo "ERROR: no .ko produced for ${DRIVER_REL_PATH}" >&2
        exit 1
    fi

    echo "========================================================"
    echo " Done. Modules in dist/:"
    ls -lh "${SCRIPT_DIR}/dist/"
}

build_driver && collect_module
