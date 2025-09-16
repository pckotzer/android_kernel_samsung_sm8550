#!/bin/bash

set -e

KERNEL_TOOLS=/mnt/nvme/prebuilts/kernel-build-tools/linux-x86/bin/
CLANG_PATH=/mnt/nvme/prebuilts/clang/host/linux-x86/clang-r547379/bin/

export PATH="$KERNEL_TOOLS:$CLANG_PATH:$PATH"

TARGET=$1
ACTION=$2  # Optional second argument, e.g. "menuconfig"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <target> [menuconfig]"
    exit 1
fi

KERNEL_SRC=$(pwd)
O=out
OUT_DIR=$KERNEL_SRC/$O
INSTALL_MOD_PATH=modules_out
TARGET_DEFCONFIG="${TARGET}_defconfig"

TARGET_KERNEL_EXT_MODULE_ROOT="$KERNEL_SRC/../sm8550-modules"
FIRST_STAGE_MODULES_LIST="modules.list.msm.kalama"
RECOVERY_EXT_MODULES="msm_drm.ko"

case "$TARGET" in
    dm1q|dm2q)
        TARGET_KERNEL_EXT_MODULES="qcom/opensource/mmrm-driver qcom/opensource/mm-drivers/hw_fence qcom/opensource/mm-drivers/msm_ext_display qcom/opensource/mm-drivers/sync_fence qcom/opensource/audio-kernel qcom/opensource/camera-kernel qcom/opensource/dataipa/drivers/platform/msm qcom/opensource/datarmnet/core qcom/opensource/datarmnet-ext/aps qcom/opensource/datarmnet-ext/offload qcom/opensource/datarmnet-ext/shs qcom/opensource/datarmnet-ext/perf qcom/opensource/datarmnet-ext/perf_tether qcom/opensource/datarmnet-ext/sch qcom/opensource/datarmnet-ext/wlan qcom/opensource/securemsm-kernel qcom/opensource/display-drivers/msm qcom/opensource/eva-kernel qcom/opensource/video-driver qcom/opensource/graphics-kernel qcom/opensource/wlan/platform qcom/opensource/wlan/qcacld-3.0/.qca6490 qcom/opensource/bt-kernel"
        ;;
    dm3q)
        TARGET_KERNEL_EXT_MODULES="qcom/opensource/mmrm-driver qcom/opensource/mm-drivers/hw_fence qcom/opensource/mm-drivers/msm_ext_display qcom/opensource/mm-drivers/sync_fence qcom/opensource/audio-kernel qcom/opensource/camera-kernel qcom/opensource/dataipa/drivers/platform/msm qcom/opensource/datarmnet/core qcom/opensource/datarmnet-ext/aps qcom/opensource/datarmnet-ext/offload qcom/opensource/datarmnet-ext/shs qcom/opensource/datarmnet-ext/perf qcom/opensource/datarmnet-ext/perf_tether qcom/opensource/datarmnet-ext/sch qcom/opensource/datarmnet-ext/wlan qcom/opensource/securemsm-kernel qcom/opensource/display-drivers/msm qcom/opensource/eva-kernel qcom/opensource/video-driver qcom/opensource/graphics-kernel qcom/opensource/wlan/platform qcom/opensource/wlan/qcacld-3.0/.kiwi_v2 qcom/opensource/bt-kernel"
        ;;
    *)
        echo "Error: Unknown target $TARGET"
        exit 1
        ;;
esac

function section() {
    local input="$1"
    local length=${#input}
    printf '%*s\n' "$length" '' | tr ' ' '='
    echo "$input"
    printf '%*s\n' "$length" '' | tr ' ' '='
}

function kernel_make() {
    make -j$(nproc) \
        O=$O \
        ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        INSTALL_MOD_PATH=$INSTALL_MOD_PATH \
        $@ < /dev/null
}

function ext_module_make() {
    module_path=$TARGET_KERNEL_EXT_MODULE_ROOT/$1

    kernel_make \
        OUT_DIR=$OUT_DIR \
        KERNEL_SRC=$KERNEL_SRC \
        KERNEL_UAPI_HEADERS_DIR=$OUT_DIR \
        M=$(realpath --relative-to=$KERNEL_SRC $module_path) \
        -C $module_path \
        ${@:2}
}

function get_modlib_file_path() {
    local file_path=$(echo $OUT_DIR/$INSTALL_MOD_PATH/**/**/**/$1)

    if [[ $(echo $file_path | wc -w) -ne 1 ]]; then
        echo "None or multiple files were found for $1 on modlib: $file_path"
        exit 1
    fi

    echo $file_path
}

function generate_module_deps() {
    modules_dep_file=$(get_modlib_file_path modules.dep)
    if [[ "$(grep -e "^$1:" -e "/$1:" $modules_dep_file)" == "" ]]; then
        echo "Needed $1 was not found in modules.dep"
        exit 1
    fi

    module_data=$(grep -e "^$1:" -e "/$1:" $(get_modlib_file_path modules.dep))
    module_name=$(basename $1)

    if [[ -f $2 ]] && [[ "$(grep "^$module_name" $2)" != "" ]]; then
        return
    fi

    echo $module_name >> $2

    module_deps=$(echo $module_data | cut -d ":" -f 2)
    for dep in $module_deps; do
        generate_module_deps $dep $2
    done
}

function generate_modules_load() {
    modules_order_file=$(get_modlib_file_path modules.order)
    modules_dep_file=$(get_modlib_file_path modules.dep)
    rm -f $OUT_DIR/modules.load.*

    echo "Generating first stage modules list at $OUT_DIR/modules.load.vendor_boot"
    for mod in $(cat $FIRST_STAGE_MODULES_LIST); do
        if [[ "$(grep -e "^$mod:" -e "/$mod:" $(get_modlib_file_path modules.dep))" != "" ]]; then
            generate_module_deps $mod $OUT_DIR/modules.load.vendor_boot
        fi
    done

    echo "Generating recovery modules list at $OUT_DIR/modules.load.recovery"
    cat $modules_order_file | rev | cut -d / -f 1 | rev > $OUT_DIR/modules.load.recovery
    for ext_mod in $RECOVERY_EXT_MODULES; do
        generate_module_deps $ext_mod $OUT_DIR/modules.load.recovery
    done
    sed -i '/zram.ko/d; /zsmalloc.ko/d' $OUT_DIR/modules.load.recovery

    echo "Generating vendor DLKM modules list at $OUT_DIR/modules.load"
    ext_modules=$(cat $modules_dep_file | cut -d ":" -f 1)
    for ext_mod in $ext_modules; do
        generate_module_deps $ext_mod $OUT_DIR/modules.load
    done

    sed -i '/zram.ko/d; /zsmalloc.ko/d' $OUT_DIR/modules.load

    for mod in $(cat $OUT_DIR/modules.load.vendor_boot); do
        sed -i "/$mod/d" $OUT_DIR/modules.load
    done
}

if [[ -z $TARGET_DEFCONFIG ]] || [[ -z $TARGET_KERNEL_EXT_MODULES ]] || [[ -z $TARGET_KERNEL_EXT_MODULE_ROOT ]] || [[ -z $FIRST_STAGE_MODULES_LIST ]]; then
    echo "Misconfigured target, make sure that all needed variables are set"
    exit 1
fi

section "Kernel config"
if [[ "$ACTION" == "menuconfig" ]]; then
    CUSTOM_CONFIG="/mnt/nvme/kernel/samsung/sm8550/arch/arm64/configs/dm1q_defconfig"
    echo "Using custom config: $CUSTOM_CONFIG"
    mkdir -p $O
    cp "$CUSTOM_CONFIG" "$O/.config"
else
    make O=$O ARCH=arm64 $TARGET_DEFCONFIG
fi

# ================
# Handle menuconfig
# ================
if [[ "$ACTION" == "menuconfig" ]]; then
    section "Opening menuconfig"
    make O=$O ARCH=arm64 menuconfig
    exit 0
fi

section "Kernel build"
kernel_make

section "Kernel modules install"
kernel_make modules_install

section "External kernel modules build"
echo "Module root is $TARGET_KERNEL_EXT_MODULE_ROOT"
for module in $TARGET_KERNEL_EXT_MODULES; do
    section "Building $module"
    ext_module_make $module

    section "Installing $module"
    ext_module_make $module modules_install
done

section "Generating modules.load files"
generate_modules_load
echo -e "debugcc-kalama.ko\nsched-walt.ko" >> $OUT_DIR/modules.load

