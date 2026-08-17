# TrollMask — 巨魔（TrollStore）专用：对选定 App 伪装机器码 + 虚拟定位

> 仅对「你在 App 里选定的那一个已安装 App」生效，不改整机、不碰其它 App、可逆（重装/清 tmp 即恢复）。

---

## 这是什么

TrollStore 能装带特殊 entitlement 的 App，并且其自定义 dyld 允许通过
`DYLD_INSERT_LIBRARIES` 把 dylib 注入到**任意其它 App 的进程**里。

TrollMask 利用这一点：

1. 主 App（TrollStore 安装）列出本机已安装 App，让你挑一个目标。
2. 你配置「设备伪装参数」和「虚拟定位坐标」，点「注入并启动」。
3. 主 App 把配置写到 `/var/tmp/trollmask_config.plist`，把 dylib 拷到 `/var/tmp`，
   然后用 `posix_spawn` **带着 dylib 重新启动目标 App**。
4. dylib 在目标 App 进程内 hook 设备信息 API 与 `CLLocationManager`，
   只影响这一个进程——退出重开（不带注入）就恢复原样。

### 这能伪装什么

| 目标 | 方式 |
|------|------|
| `UIDevice.identifierForVendor`（IDFV） | Method Swizzle 返回伪造 UUID |
| `UIDevice.name` / `model` | Method Swizzle |
| `sysctlbyname("hw.machine" / "hw.model")` | Hook 返回 `iPhone14,2` 之类 |
| GPS 定位 | Hook `CLLocationManager` 的 `location` / `startUpdatingLocation` / `requestLocation`，直接喂假坐标 |

> ⚠️ 真实硬件序列号（serial number）需要 bootloader 级修改（checkm8 / kernboot），
> 普通 App 进程内无法改写。这里覆盖的是「App 能读到的设备标识 API」，足以骗过绝大多数
> 基于 IDFV / sysctl / UIDevice 做机器码 / 设备指纹的逻辑。

---

## 目录结构

```
TrollMask/
├── control                         # deb 包信息
├── Makefile                        # 主 App 构建（theos application）
├── entitlements.plist             # 主 App 高权限 entitlement（TrollStore 用）
├── build.sh                       # 一键构建脚本（先编 dylib，再编 App 打包）
├── layout/Applications/TrollMask.app/   # dylib 随 App 一起打包
├── TrollMaskApp/
│   ├── AppDelegate.swift
│   ├── ContentView.swift           # 主界面
│   ├── DeviceSpoofer.swift         # App 枚举 / 配置 / 注入应用
│   ├── AppLauncher.h / .m          # kill + posix_spawn 注入
│   └── TrollMask-Bridging-Header.h
└── TrollMaskDylib/
    ├── Tweak.m                     # 注入逻辑（hook）
    ├── Makefile
    └── entitlements.plist
```

---

## 构建（需要在 macOS + Theos 环境）

本仓库只是源码。**我无法在 Windows 上编译出 ipa / deb**，请在装有 Xcode + Theos 的 Mac 上：

```bash
# 1. 安装 Theos（见 https://theos.dev），确保 $THEOS 已设置
# 2. 进入工程目录
cd TrollMask
chmod +x build.sh
./build.sh
```

`build.sh` 会：先 `make` 出 `TrollMaskDylib.dylib` → 拷进 `layout` → 再 `make package` 出主 App 的 deb。

> 若只要 dylib 单独调试，也可进 `TrollMaskDylib/` 直接 `make`。

---

## 安装与使用

1. 用 TrollStore 安装打包出的主 App（deb 内 `/Applications/TrollMask.app`）。
2. 打开 TrollMask → 在列表里选目标 App（如某游戏 / 某电商 App）。
3. 打开「机器码伪装」：默认给一个随机 IDFV + 机型；点「🎲 一键新机」可重新随机。
4. 打开「虚拟定位」：填纬度/经度（默认北京）。
5. 点「注入并启动选定 App」。目标 App 会被杀掉并以注入方式重启。
6. 验证：在目标 App 内查看「关于 / 设备信息 / 定位」，应显示伪造值。

### 撤销
- 直接正常打开目标 App（不经过 TrollMask 注入）即为原始状态。
- 或 `rm /var/tmp/TrollMaskDylib.dylib /var/tmp/trollmask_config.plist`。
- 或重装目标 App。

---

## 适用 / 不兼容

- 需要 **TrollStore** 已安装（其自定义 dyld 是注入生效的前提）。
- 支持 iOS 14.0–16.x，部分 17.x 视 TrollStore 版本而定。
- 若目标 App 用自实现的反注入（校验 dyld 环境、检测 `DYLD_INSERT_LIBRARIES`、
  或走私有底层接口读序列号），本方案可能失效——这属于目标 App 自身的对抗，非本工具 bug。

---

## 声明

本工具仅供 **你本人拥有的设备** 做以下用途：**隐私保护、App 测试、定位功能调试**。
请勿用于突破任何服务的使用条款、刷量、作弊或任何违法用途。使用者需自行承担一切后果。

---

## GitHub Actions 自动构建（推荐）

仓库已内置 `.github/workflows/build.yml`：每次 `push` 到 `main`/`master`、开 PR、或手动触发，
都会在 macOS runner 上自动装好 Theos + iOS 16.5 SDK，跑 `build.sh`，并把打好的 `.deb`
作为 **Artifacts** 产出——你不用自己装编译环境。

### 推到 GitHub 后自动出包

在**已登录 `gh` 的机器**（Mac 或本机均可）执行：

```bash
# 进入工程（若是从 bundle 还原的，先 git clone TrollMask.bundle TrollMask）
cd TrollMask

# 首次：在 GitHub 建公开仓库并推送
gh repo create TrollMask --public --source=. --remote=origin --push
# 若仓库已存在，手动加远端再推：
#   git remote add origin git@github.com:<你的用户名>/TrollMask.git
#   git branch -M main
#   git push -u origin main

# push 之后去 GitHub 仓库 → Actions 标签页，等 "Build TrollMask (deb)" 跑完，
# 进该次 run → 右侧 Artifacts 下载 TrollMask-deb（里面是 .deb）。
# 用 TrollStore 装上即可。
```

> 想每次发 tag 自动出 **Release**（而不只是 Artifact），可把 workflow 末尾的
> `upload-artifact` 换成 `softprops/action-gh-release`，在 `on:` 里加 `tags: ['v*']` 即可。

### 本地手动构建（仍可用）

```bash
cd TrollMask
chmod +x build.sh
./build.sh
```

> 若 CI 首次报 SDK 版本不匹配：把 `build.yml` 里的 `sdk-version` 与本仓库两个 `Makefile`
> 的 `TARGET := iphone:clang:<版本>` 改成同一个存在的 iOS SDK 版本（如 `16.5`）即可。
