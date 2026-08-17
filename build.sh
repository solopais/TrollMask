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

# Theos 把 dylib 输出到 .theos/obj 下，路径因版本可能略有差异，用 find 兜底定位
DYLIB_SRC=$(find TrollMaskDylib/.theos -type f -name 'TrollMaskDylib.dylib' 2>/dev/null | head -1)
if [ -z "$DYLIB_SRC" ]; then
  echo "!!! 找不到 TrollMaskDylib.dylib，.theos 实际产物如下："
  find TrollMaskDylib/.theos -type f 2>/dev/null | head -50
  exit 1
fi
echo "==> 找到 dylib: $DYLIB_SRC"

echo "==> [2/3] 拷贝 dylib 到 layout（随主 App 打包）"
mkdir -p layout/Applications/TrollMask.app
cp "$DYLIB_SRC" layout/Applications/TrollMask.app/TrollMaskDylib.dylib
chmod 755 layout/Applications/TrollMask.app/TrollMaskDylib.dylib
rm -f layout/Applications/TrollMask.app/PLACEHOLDER.txt

echo "==> [3/3] 构建主 App 并打包 deb"
# GitHub macOS runner 上 Homebrew 的 fakeroot 是 arm64、runner 进程需 arm64e，会崩溃；
# 也不能把 FAKEROOT= 设空（会破坏 Theos 的 `$(FAKEROOT) bash -c ...` 命令结构）。
# 这里放一个 fakeroot 替身到 PATH 最前：吃掉 fakeroot 自己的 -i/-s 等参数，
# 只 exec 后面的真正命令（bash -c "dpkg-deb ..."），不伪造 root 属主。
# TrollStore 安装 .deb 不依赖包内文件属主，故完全可行。
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/fakeroot <<'SH'
#!/bin/bash
# fakeroot passthrough shim (CI only): drop fakeroot's own flags, run the real command.
args=("$@")
i=0
n=${#args[@]}
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

make clean || true
make package FINALPACKAGE=1

echo "==> 完成。deb 位于 ./packages/ 或 .theos/ 目录，用 TrollStore / Sileo / Filza 安装主 App 即可。"
ls -lh packages/*.deb .theos/*.deb 2>/dev/null || true
