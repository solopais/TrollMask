#!/bin/bash
#
# build.sh — 在 macOS 上构建 TrollMask（应用级伪装 + 虚拟定位 IPA）
#
# 方案：
#   - dylib（TrollMaskDylib）仍用 Theos 编译（Theos 对 ObjC tweak 支持良好）
#   - 主 App（SwiftUI）改用 xcodebuild 编译（Theos application.mk 在本环境对 Swift 支持有坑，
#     会静默跳过 App 编译导致 IPA 内 .app 为空壳 -> TrollStore 报 302 找不到 Info.plist）
#   - 用 ldid 把 entitlements 签进二进制，TrollStore 安装时会用其自签根证书重签并保留这些 entitlement
#
# 用法：cd TrollMask && ./build.sh
#
set -e

export THEOS="${THEOS:-$PWD/theos}"

echo "==> [1/5] 用 Theos 构建注入 dylib (TrollMaskDylib)"
cd TrollMaskDylib
make clean || true
make
cd ..
DYLIB_SRC=$(find TrollMaskDylib/.theos -type f -name 'TrollMaskDylib.dylib' 2>/dev/null | head -1)
if [ -z "$DYLIB_SRC" ]; then
  echo "!!! 找不到 TrollMaskDylib.dylib，.theos 实际产物如下："
  find TrollMaskDylib/.theos -type f 2>/dev/null | head -50
  exit 1
fi
echo "==> dylib: $DYLIB_SRC"

echo "==> [2/5] 用 xcodegen 生成 Xcode 工程"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "!!! 未找到 xcodegen，请先 brew install xcodegen"
  exit 1
fi
xcodegen generate
echo "==> 已生成 TrollMask.xcodeproj"

echo "==> [3/5] xcodebuild 编译主 App（iphoneos / arm64 / iOS 15+）"
xcodebuild \
  -project TrollMask.xcodeproj \
  -target TrollMask \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  build 2>&1 | tee /tmp/xcodebuild.log | tail -20

APP=$(find ~/Library/Developer/Xcode/DerivedData/TrollMask-*/Build/Products/Release-iphoneos/TrollMask.app -maxdepth 0 2>/dev/null | head -1)
# 兼容不同 DerivedData 路径
if [ -z "$APP" ]; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -name 'TrollMask.app' -path '*Release-iphoneos*' 2>/dev/null | head -1)
fi
if [ -z "$APP" ] || [ ! -x "$APP/TrollMask" ]; then
  echo "!!! 主 App 未编译成功。xcodebuild 末段日志："
  tail -40 /tmp/xcodebuild.log
  exit 1
fi
echo "==> 主 App 已编译: $APP"
echo "    - 主二进制存在: $([ -x "$APP/TrollMask" ] && echo 是 || echo 否)"
echo "    - Info.plist 存在: $([ -f "$APP/Info.plist" ] && echo 是 || echo 否)"

echo "==> [4/5] ldid 把 entitlements 签进二进制（TrollStore 重签时保留）"
if command -v ldid >/dev/null 2>&1; then
  ldid -Sentitlements.plist "$APP/TrollMask"
  echo "==> 已用 ldid 签名（含 platform-application 等高权限 entitlement）"
else
  echo "!!! 未找到 ldid，跳过签名（TrollStore 安装时会自行处理，但建议 brew install ldid）"
fi

echo "==> 注入 dylib 到 .app（运行时 App 会把它拷到 /var/tmp 注入目标进程）"
cp "$DYLIB_SRC" "$APP/TrollMaskDylib.dylib"
chmod 755 "$APP/TrollMaskDylib.dylib"

echo "==> [5/5] 打包 IPA（Payload/TrollMask.app）"
rm -rf /tmp/ipa && mkdir -p /tmp/ipa/Payload
cp -r "$APP" /tmp/ipa/Payload/TrollMask.app
( cd /tmp/ipa && zip -r "$PWD/TrollMask.ipa" Payload >/dev/null )
echo "==> IPA 关键内容校验："
unzip -l TrollMask.ipa 2>/dev/null | grep -E "TrollMask.app/Info.plist|TrollMask.app/TrollMask|TrollMask.app/TrollMaskDylib.dylib|libswift" | head -40
echo "==> IPA 大小："
ls -lh TrollMask.ipa
echo "==> 完成。"
