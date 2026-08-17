//
//  DeviceSpoofer.swift
//  TrollMask — 配置生成 / 已安装 App 枚举 / 注入应用
//

import Foundation
import UIKit

struct InstalledApp: Identifiable, Hashable {
    let id: String          // bundleIdentifier
    let name: String
    let execPath: String    // 可执行文件绝对路径
    let execName: String    // 可执行文件名（用于 kill）
}

struct SpoofConfig {
    var spoofDevice: Bool = true
    var spoofLocation: Bool = true

    // 设备伪装字段
    var fakeIDFV: String = UUID().uuidString.uppercased()
    var fakeName: String = "iPhone"
    var fakeModel: String = "iPhone"
    var hwMachine: String = "iPhone14,2"
    var hwModel: String = "D16AP"

    // 虚拟定位
    var latitude: Double = 39.9042
    var longitude: Double = 116.4074

    func toDictionary() -> [String: Any] {
        return [
            "spoofDevice": spoofDevice,
            "spoofLocation": spoofLocation,
            "fakeIDFV": fakeIDFV,
            "fakeName": fakeName,
            "fakeModel": fakeModel,
            "hwMachine": hwMachine,
            "hwModel": hwModel,
            "latitude": latitude,
            "longitude": longitude
        ]
    }
}

enum DeviceSpoofer {

    static let configPath = "/var/tmp/trollmask_config.plist"
    static let dylibDest  = "/var/tmp/TrollMaskDylib.dylib"

    /// 枚举已安装的用户 App（含系统 App 由 includeSystem 控制）
    static func installedApps(includeSystem: Bool = false) -> [InstalledApp] {
        guard
            let wsClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type
        else { return [] }
        let defaultSel = NSSelectorFromString("defaultWorkspace")
        let allSel = NSSelectorFromString("allApplications")
        guard
            let workspace = wsClass.perform(defaultSel).takeUnretainedValue() as? NSObject
        else { return [] }

        guard let apps = workspace.perform(allSel).takeUnretainedValue() as? [NSObject] else { return [] }

        var result: [InstalledApp] = []
        for proxy in apps {
            guard
                let bid = proxy.perform(NSSelectorFromString("bundleIdentifier"))?.takeUnretainedValue() as? String,
                let bundleURL = proxy.perform(NSSelectorFromString("bundleURL"))?.takeUnretainedValue() as? URL,
                let localizedName = proxy.perform(NSSelectorFromString("localizedName"))?.takeUnretainedValue() as? String
            else { continue }

            let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
            guard let info = NSDictionary(contentsOf: infoPlistURL),
                  let execName = info["CFBundleExecutable"] as? String else { continue }

            let execPath = bundleURL.appendingPathComponent(execName).path

            // 仅保留用户 App（系统 App 路径为 /Applications/，用户 App 在 .../Bundle/Application/...）
            let isUserApp = bundleURL.path.contains("Bundle/Application")
            if !includeSystem && !isUserApp { continue }

            result.append(InstalledApp(id: bid, name: localizedName, execPath: execPath, execName: execName))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 把内置 dylib 从 App 自身 bundle 复制到 /var/tmp（可读，供目标进程注入）
    static func stageDylib() -> Bool {
        guard let src = Bundle.main.path(forResource: "TrollMaskDylib", ofType: "dylib") else { return false }
        let fm = FileManager.default
        try? fm.removeItem(atPath: dylibDest)
        do {
            try fm.copyItem(atPath: src, toPath: dylibDest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dylibDest)
            return true
        } catch { return false }
    }

    /// 写配置到 /var/tmp
    static func writeConfig(_ config: SpoofConfig) -> Bool {
        let dict = config.toDictionary() as NSDictionary
        return dict.write(toFile: configPath, atomically: true)
    }

    /// 一键应用：写配置 + 复制 dylib + kill 目标 + 注入启动
    static func apply(to app: InstalledApp, config: SpoofConfig) -> (ok: Bool, message: String) {
        guard stageDylib() else {
            return (false, "无法部署 dylib 到 /var/tmp（检查 TrollStore 文件权限）")
        }
        guard writeConfig(config) else {
            return (false, "无法写入配置文件 \(configPath)")
        }
        AppLauncher.killApp(withExecName: app.execName)
        let ok = AppLauncher.launchApp(atExecPath: app.execPath, dylibPath: dylibDest, configPath: configPath)
        return ok
            ? (true, "已注入并启动：\(app.name)")
            : (false, "启动失败，可能目标 App 不支持 DYLD 注入（需 TrollStore 环境）")
    }
}

// 一组常见机型映射，用于“一键新机”随机生成
extension DeviceSpoofer {
    static let commonModels: [(model: String, hwMachine: String, hwModel: String)] = [
        ("iPhone", "iPhone14,2", "D16AP"),   // iPhone 13 Pro
        ("iPhone", "iPhone14,3", "D17AP"),   // iPhone 13 Pro Max
        ("iPhone", "iPhone15,2", "D22AP"),   // iPhone 14 Pro
        ("iPhone", "iPhone15,3", "D23AP"),   // iPhone 14 Pro Max
        ("iPhone", "iPhone16,1", "D27AP"),   // iPhone 15
        ("iPhone", "iPhone16,2", "D28AP"),   // iPhone 15 Pro
        ("iPad",   "iPad13,8",  "J320AP"),   // iPad Pro 11"
        ("iPad",   "iPad14,3",  "J407AP")    // iPad Air 5
    ]

    static func randomDeviceIdentity() -> (fakeName: String, fakeModel: String, hwMachine: String, hwModel: String) {
        let pick = commonModels.randomElement() ?? commonModels[0]
        let adjectives = ["My", "Owner", "User", "iPhone", "Device"]
        let name = (adjectives.randomElement() ?? "iPhone") + " 的 iPhone"
        return (name, pick.model, pick.hwMachine, pick.hwModel)
    }
}
