set -e

MAIN_DEFCONFIG=pineapple_gki_defconfig

LOCALVERSION_BASE=-android14-Elaina-Happy_Every_Day

LTO=""

TOOLCHAIN=$(realpath "$GITHUB_WORKSPACE/prebuilts")

ANYKERNEL_REPO="https://github.com/Voisterouslife/AnyKernel3.git"
ANYKERNEL_BRANCH="pineapple"

ZIP_NAME_PREFIX="S24_kernel"


cd "$(dirname "$0")"

export PATH=$TOOLCHAIN/build-tools/linux-x86/bin:$PATH
export PATH=$TOOLCHAIN/build-tools/path/linux-x86:$PATH
export PATH=$TOOLCHAIN/clang/host/linux-x86/clang-r487747c/bin:$PATH
export PATH=$TOOLCHAIN/clang-tools/linux-x86/bin:$PATH
export PATH=$TOOLCHAIN/kernel-build-tools/linux-x86/bin:$PATH
export LLVM_AR=llvm-ar
export LLVM_NM=llvm-nm

MAKE_ARGS="
O=out
ARCH=arm64
CC=clang
LLVM=1
LLVM_IAS=1
"


echo "--- 正在清理 (rm -rf out) ---"
rm -rf out


TARGET_DEFCONFIG=${1:-$MAIN_DEFCONFIG}
echo "--- 正在应用 defconfig: $TARGET_DEFCONFIG ---"
make ${MAKE_ARGS} $TARGET_DEFCONFIG
if [ $? -ne 0 ]; then
    echo "错误: 应用 defconfig '$TARGET_DEFCONFIG' 失败。"
    exit 1
fi

./scripts/config --file out/.config \
  -d UH \
  -d RKP \
  -d KDP \
  -d SECURITY_DEFEX \
  -d INTEGRITY \
  -d FIVE \
  -d TRIM_UNUSED_KSYMS

make -j$(nproc) ${MAKE_ARGS} LOCALVERSION="${LOCALVERSION_BASE}"
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
    echo "--- 内核编译失败！ ---"
    echo "请检查屏幕上的错误信息。"
    exit 1
fi

echo -e "\n--- 内核编译成功！ ---\n"

echo "--- 正在准备打包环境 ---"
cd out

if [ ! -d AnyKernel3 ]; then
  echo "--- 正在克隆 AnyKernel3 仓库 (分支: ${ANYKERNEL_BRANCH}) ---"
  git clone --depth=1 "${ANYKERNEL_REPO}" -b "${ANYKERNEL_BRANCH}" AnyKernel3
fi

cp arch/arm64/boot/Image AnyKernel3/Image
cd AnyKernel3

echo "--- 正在运行 patch_linux ---"

chmod +x ./patch_linux
./patch_linux
mv oImage zImage
rm -f Image oImage patch_linux

echo "--- patch_linux 执行完毕, 已生成 zImage ---"

kernel_release=$(cat ../include/config/kernel.release)
final_name="${ZIP_NAME_PREFIX}_${kernel_release}_$(date '+%Y%m%d')"

echo "--- 正在创建 Zip 刷机包: ${final_name}.zip ---"
zip -r9 "../${final_name}.zip" . -x "*.zip"

ZIP_FILE_PATH=$(realpath "../${final_name}.zip")
UPLOAD_FILES="$ZIP_FILE_PATH"

echo "--- 正在创建 boot.img: ${final_name}.img ---"
cp zImage tools/kernel
cd tools
chmod +x libmagiskboot.so
lz4 boot.img.lz4
./libmagiskboot.so repack boot.img
mv new-boot.img "../../${final_name}.img"
cd ../..

IMG_FILE_PATH=$(realpath "${final_name}.img")
UPLOAD_FILES="$UPLOAD_FILES $IMG_FILE_PATH"

echo "======================================================"
echo "成功！"
echo "刷机包输出到: ${ZIP_FILE_PATH}"
echo "Boot 镜像输出到: ${IMG_FILE_PATH}"
echo "======================================================"

exit 0
