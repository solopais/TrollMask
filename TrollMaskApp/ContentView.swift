//
//  ContentView.swift
//  TrollMask — 主界面（SwiftUI）
//

import SwiftUI

struct ContentView: View {
    @State private var apps: [InstalledApp] = []
    @State private var selectedApp: InstalledApp?
    @State private var searchText = ""

    @State private var spoofDevice = true
    @State private var spoofLocation = true
    @State private var fakeIDFV = UUID().uuidString.uppercased()
    @State private var fakeName = "iPhone"
    @State private var fakeModel = "iPhone"
    @State private var hwMachine = "iPhone14,2"
    @State private var hwModel = "D16AP"
    @State private var latitude = "39.9042"
    @State private var longitude = "116.4074"

    @State private var statusMessage = ""
    @State private var isBusy = false

    var filteredApps: [InstalledApp] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            List(selection: $selectedApp) {
                Section("选择目标 App（仅对该 App 生效）") {
                    ForEach(filteredApps) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.headline)
                            Text(app.id).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(app as InstalledApp?)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索 App 名称 / Bundle ID")
            .navigationTitle("TrollMask 伪装")
            .onAppear { reloadApps() }

            Form {
                Section("机器码伪装") {
                    Toggle("启用", isOn: $spoofDevice)
                    LabeledContent("伪造 IDFV", value: fakeIDFV)
                    TextField("设备名", text: $fakeName)
                    TextField("Model", text: $fakeModel)
                    TextField("hw.machine", text: $hwMachine)
                    TextField("hw.model", text: $hwModel)
                    Button("🎲 一键新机（随机生成）") { regenerate() }
                        .disabled(!spoofDevice)
                }

                Section("虚拟定位") {
                    Toggle("启用", isOn: $spoofLocation)
                    TextField("纬度 Latitude", text: $latitude)
                        .keyboardType(.decimalPad)
                    TextField("经度 Longitude", text: $longitude)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button(action: apply) {
                        if isBusy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("注入并启动选定 App").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedApp == nil || isBusy)
                    .buttonStyle(.borderedProminent)
                }

                if !statusMessage.isEmpty {
                    Section("结果") { Text(statusMessage).font(.footnote) }
                }
            }
        }
    }

    private func reloadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let list = DeviceSpoofer.installedApps(includeSystem: false)
            DispatchQueue.main.async { self.apps = list }
        }
    }

    private func regenerate() {
        let r = DeviceSpoofer.randomDeviceIdentity()
        fakeName = r.fakeName
        fakeModel = r.fakeModel
        hwMachine = r.hwMachine
        hwModel = r.hwModel
        fakeIDFV = UUID().uuidString.uppercased()
    }

    private func apply() {
        guard let app = selectedApp else { return }
        guard let lat = Double(latitude), let lon = Double(longitude) else {
            statusMessage = "经纬度格式不正确"
            return
        }
        let config = SpoofConfig(
            spoofDevice: spoofDevice,
            spoofLocation: spoofLocation,
            fakeIDFV: fakeIDFV,
            fakeName: fakeName,
            fakeModel: fakeModel,
            hwMachine: hwMachine,
            hwModel: hwModel,
            latitude: lat,
            longitude: lon
        )
        isBusy = true
        statusMessage = "正在注入 \(app.name) ..."
        DispatchQueue.global(qos: .userInitiated).async {
            let res = DeviceSpoofer.apply(to: app, config: config)
            DispatchQueue.main.async {
                isBusy = false
                statusMessage = res.message
            }
        }
    }
}
