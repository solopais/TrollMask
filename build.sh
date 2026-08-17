#!/bin/bash
#
# build.sh — 在 macOS + Theos 环境下构建 TrollMask（主 App + 注入 dylib）并打包 IPA / deb
#
# 关键修复：必须先编译出真正的 .app（含二进制 + Info.plist + Swift 运行库），
# 再注入 dylib；绝不能提前在 layout/Applications/TrollMask.app/ 建目录，
# 否则 Theos application.mk 会把它当成“已就绪 app”跳过 Swift 编译，产出空壳 .app
# （TrollStore 报 302 = 找不到 Info.plist）。
#
# 用法：
#   cd TrollMask && ./build.sh
#
set -e

echo "==> [1/4] 构建注入 dylib (TrollMaskDylib)"
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

# GitHub macOS runner 上 Homebrew 的 fakeroot 是 arm64、runner 进程需 arm64e，会崩溃；
# 且不能把 FAKEROOT= 设空（会破坏 Theos 的 `$(FAKEROOT) -i X -s X bash -c ...` 命令结构）。
# 放一个 fakeroot 替身到 PATH 最前：吃掉 fakeroot 自身 -i/-s 等参数，只 exec 真正的命令。
# TrollStore 装 .deb 不依赖包内文件属主，故完全可行。
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/fakeroot <<'SH'
#!/bin/bash
args=("$@"); i=0; n=${#args[@]}
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    -i|-s|-l|-f|-p|-P|-c) i=$((i+2)) ;;   # flags taking an argument
    -u|-S|-e|--help|-v|-V) i=$((i+1)) ;;  # flags without argument
    --) i=$((i+1)); break ;;
    *) break ;;
  esac
done
exec "${args[@]:$i}"
SH
chmod +x /tmp/fakebin/fakeroot
export PATH="/tmp/fakebin:$PATH"
echo "==> fakeroot 替身: $(command -v fakeroot)"

echo "==> [2/4] 先显式编译主 App（make），禁止提前在 layout 建 .app"
make clean || true
echo "--- [诊断] make messages=yes 输出 ---"
make messages=yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -50 || true
echo "--- [诊断] 显式 make TrollMask ---"
make TrollMask 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -50 || true
APP_BUILD=$(find .theos -type d -name 'TrollMask.app' 2>/dev/null | head -1)
if [ -z "$APP_BUILD" ] || [ ! -f "$APP_BUILD/TrollMask" ]; then
  echo "!!! 主 App 未编译成功，.theos 内容如下："
  find .theos -maxdepth 5 -type f 2>/dev/null | head -60
  exit 1
fi
echo "==> 主 App 已编译: $APP_BUILD"
echo "    - 主二进制: $(file "$APP_BUILD/TrollMask" 2>/dev/null | cut -d: -f2)"
echo "    - Info.plist: $([ -f "$APP_BUILD/Info.plist" ] && echo 存在 || echo 缺失!)"

# 把 dylib 注入到编译好的 .app 里（运行时 App 会把它拷到 /var/tmp 用于注入目标进程）
cp "$DYLIB_SRC" "$APP_BUILD/TrollMaskDylib.dylib"
chmod 755 "$APP_BUILD/TrollMaskDylib.dylib"

echo "==> [3/4] make package 生成 deb（此时 .app 已编译，Theos 只会做 stage + 叠加 dylib）"
# 现在再把 dylib 放进 layout 叠加层，供 make package 打包进 deb
rm -rf layout/Applications/TrollMask.app
mkdir -p layout/Applications/TrollMask.app
cp "$DYLIB_SRC" layout/Applications/TrollMask.app/TrollMaskDylib.dylib
chmod 755 layout/Applications/TrollMask.app/TrollMaskDylib.dylib
make package FINALPACKAGE=1
echo "==> deb:"
ls -lh packages/*.deb .theos/*.deb 2>/dev/null || true

echo "==> [4/4] 由打包后的 .app 生成 IPA（含 Swift 运行库 + dylib，供 TrollStore 直接装）"
# make package 之后，完整的 .app 存在于 .theos/_/Applications/TrollMask.app（带 Swift libs）
APP_PKG=$(find .theos/_ -type d -name 'TrollMask.app' 2>/dev/null | head -1)
if [ -z "$APP_PKG" ] || [ ! -f "$APP_PKG/TrollMask" ]; then
  echo "!!! 打包后的 .app 未找到，退回使用编译产物 .app"
  APP_PKG="$APP_BUILD"
fi
if [ ! -f "$APP_PKG/Info.plist" ]; then
  echo "!!! 致命：.app 内无 Info.plist，TrollStore 会报 302。中止。"
  exit 1
fi
rm -rf /tmp/ipa && mkdir -p /tmp/ipa/Payload
cp -r "$APP_PKG" /tmp/ipa/Payload/TrollMask.app
( cd /tmp/ipa && zip -r "$PWD/TrollMask.ipa" Payload >/dev/null )
echo "==> IPA 关键内容校验："
unzip -l TrollMask.ipa 2>/dev/null | grep -E "TrollMask.app/Info.plist|TrollMask.app/TrollMask|TrollMask.app/TrollMaskDylib.dylib|libswift|SwiftSupport" | head -40
echo "==> IPA 大小："
ls -lh TrollMask.ipa
echo "==> 完成。"
