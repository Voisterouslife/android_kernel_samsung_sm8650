#!/bin/bash
set -e

MAIN_DEFCONFIG=pineapple_gki_defconfig
LOCALVERSION_BASE=-Elaina-Happy_Every_Day

TOOLCHAIN=$(realpath "$GITHUB_WORKSPACE/prebuilts")
ANYKERNEL_REPO="https://github.com/Voisterouslife/AnyKernel3.git"
ZIP_NAME_PREFIX="S24_kernel"

export PATH="$TOOLCHAIN/build-tools/linux-x86/bin:$TOOLCHAIN/build-tools/path/linux-x86:$TOOLCHAIN/clang/host/linux-x86/clang-r487747c/bin:$TOOLCHAIN/clang-tools/linux-x86/bin:$TOOLCHAIN/kernel-build-tools/linux-x86/bin:$PATH"

export USE_CCACHE=1
export CCACHE_EXEC=$(which ccache)

export O=out
export ARCH=arm64
export CC='ccache clang'
export LLVM=1
export LLVM_IAS=1

echo "--- 正在清理 (rm -rf out) ---"
rm -rf out

TARGET_DEFCONFIG=${1:-$MAIN_DEFCONFIG}
echo "--- 正在应用 defconfig: $TARGET_DEFCONFIG ---"
make O=out $TARGET_DEFCONFIG
if [ $? -ne 0 ]; then
    echo "错误: 应用 defconfig '$TARGET_DEFCONFIG' 失败。"
    exit 1
fi

echo "--- 正在应用自定义内核配置 ---"
scripts/config --file out/.config \
  -d UH \
  -d RKP \
  -d KDP \
  -d SECURITY_DEFEX \
  -d INTEGRITY \
  -d FIVE \
  -d TRIM_UNUSED_KSYMS

echo "--- 开始内核编译 (make -j$(nproc)) ---"
BUILD_START=$(date +"%s")
make O=out -j$(nproc) LOCALVERSION="${LOCALVERSION_BASE}"
BUILD_END=$(date +"%s")
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
    echo "--- 内核编译失败！ ---"
    exit 1
fi

BUILD_TIME=$((BUILD_END - BUILD_START))
echo -e "\n--- 内核编译成功！耗时: ${BUILD_TIME} 秒 ---\n"

echo "--- 正在准备打包环境 ---"

echo "--- 检查 out 目录是否存在 ---"
ls -ld out

cd out

if [ ! -d AnyKernel3 ]; then
  echo "--- 首次克隆 AnyKernel3 仓库 ---"
  git clone --depth=1 "${ANYKERNEL_REPO}" AnyKernel3
else
  echo "--- AnyKernel3 已存在，正在拉取更新 ---"
  cd AnyKernel3 && git pull && cd ..
fi

cp arch/arm64/boot/Image AnyKernel3/Image
cd AnyKernel3

if [ "$ENABLE_SUKISU" = "true" ]; then
    echo "--- [SukiSU Mode] 正在下载并运行 patch_linux ---"
    wget -O patch_linux "https://github.com/SukiSU-Ultra/SukiSU_patch/raw/refs/heads/main/kpm/patch_linux"
    if [ $? -ne 0 ]; then
        echo "错误: 下载 patch_linux 失败！"
        exit 1
    fi

    echo "--- 正在运行 patch_linux ---"
    chmod +x ./patch_linux && ./patch_linux
    
    if [ -f oImage ]; then
        mv oImage zImage
    fi
    
    rm -f Image oImage patch_linux
    echo "--- patch_linux 执行完毕, 已生成 zImage ---"

else
    echo "--- [Original Mode] 跳过 patch_linux ---"
    echo "--- 正在重命名 Image -> zImage---"
    mv Image zImage
fi

kernel_release=$(cat ../include/config/kernel.release)
final_name="${ZIP_NAME_PREFIX}_${kernel_release}_$(date '+%Y%m%d')"

echo "--- 正在创建 Zip 刷机包: ${final_name}.zip ---"
zip -r9 "../${final_name}.zip" . -x "*.zip"
ZIP_FILE_PATH=$(realpath "../${final_name}.zip")

echo "--- 正在创建 boot.img: ${final_name}.img ---"
cd tools

chmod +x libmagiskboot.so || true

echo "--- 解压 boot.img.lz4 到 boot.img ---"
lz4 -d boot.img.lz4 boot.img

echo "--- 使用 magiskboot unpack 解包 boot.img ---"
./libmagiskboot.so unpack boot.img
cp ../zImage ./kernel 

echo "--- 使用 magiskboot repack 进行重打包 ---"
./libmagiskboot.so repack boot.img new-boot.img

if [ ! -f new-boot.img ]; then
  echo "错误: repack 未能生成 new-boot.img"
  exit 1
fi

echo "--- 重打包成功，正在移动 boot.img ---"
mv new-boot.img "../../${final_name}.img"
cd ../..

IMG_FILE_PATH=$(realpath "${final_name}.img")

echo "======================================================"
echo "成功！"
echo "刷机包输出到: ${ZIP_FILE_PATH}"
echo "Boot 镜像输出到: ${IMG_FILE_PATH}"
echo "======================================================"

exit 0