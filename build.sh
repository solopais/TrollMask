#!/bin/bash
#
# build.sh — 在 macOS + Theos 环境下构建 TrollMask（主 App + 注入 dylib）并打包 deb
#
# 前置条件：
#   - macOS，已安装 Xcode / Command Line Tools 与 iOS SDK
#   - 已安装 Theos（https://theos.dev），且 $THEOS 已指向 theos 目录
#   - 已安装 iOS 16+ 的 tweak 开发依赖（substrate 头文件由 theos 提供）
#
# 用法：
#   cd TrollMask
#   ./build.sh
#
set -e

echo "==> [1/3] 构建注入 dylib (TrollMaskDylib)"
cd TrollMaskDylib
make clean || true
make
cd ..

DYLIB_SRC="TrollMaskDylib/.theos/obj/TrollMaskDylib.dylib"
if [ ! -f "$DYLIB_SRC" ]; then
  echo "!!! 找不到编译产物: $DYLIB_SRC"
  exit 1
fi

echo "==> [2/3] 拷贝 dylib 到 layout（随主 App 打包）"
mkdir -p layout/Applications/TrollMask.app
cp "$DYLIB_SRC" layout/Applications/TrollMask.app/TrollMaskDylib.dylib
chmod 755 layout/Applications/TrollMask.app/TrollMaskDylib.dylib
rm -f layout/Applications/TrollMask.app/PLACEHOLDER.txt

echo "==> [3/3] 构建主 App 并打包 deb"
make clean || true
make package FINALPACKAGE=1

echo "==> 完成。deb 位于 ./packages/ 或 .theos/ 目录，用 TrollStore / Sileo / Filza 安装主 App 即可。"
