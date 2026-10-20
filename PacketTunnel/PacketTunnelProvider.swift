// SPDX-License-Identifier: GPL-3.0-or-later
// Основано на sing-box-for-apple (Library/Network/ExtensionProvider.swift), GPL-3.0.

import Foundation
import Libbox
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private(set) var commandServer: LibboxCommandServer?
    private lazy var platformInterface = PlatformInterface(self)
    private var configContent: String?

    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("litenergy", isDirectory: true)
    }

    private var savedConfigURL: URL {
        baseURL.appendingPathComponent("config.json")
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
        let fm = FileManager.default
        let base = baseURL
        let working = base.appendingPathComponent("working", isDirectory: true)
        let temp = fm.temporaryDirectory.appendingPathComponent("litenergy", isDirectory: true)
        for dir in [base, working, temp] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // конфиг: из запуска приложением → из настроек VPN → последний сохранённый (автоподключение)
        var config = options?["configContent"] as? String
        if config == nil || config!.isEmpty {
            config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["configContent"] as? String
        }
        if config == nil || config!.isEmpty {
            config = try? String(contentsOf: savedConfigURL, encoding: .utf8)
        }
        guard let config, !config.isEmpty else {
            throw startupError("Нет конфигурации. Откройте приложение и подключитесь ещё раз.")
        }
        configContent = config
        try? config.write(to: savedConfigURL, atomically: true, encoding: .utf8)

        let setup = LibboxSetupOptions()
        setup.basePath = base.path
        setup.workingPath = working.path
        setup.tempPath = temp.path
        setup.logMaxLines = 300
        setup.debug = false
        setup.crashReportSource = "NetworkExtension"
        setup.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        setup.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        setup.oomKillerEnabled = true

        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError {
            throw startupError("setup: \(setupError.localizedDescription)")
        }

        var serverError: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &serverError)
        if let serverError {
            throw startupError("command server: \(serverError.localizedDescription)")
        }
        do {
            try commandServer!.start()
        } catch {
            throw startupError("command server start: \(error.localizedDescription)")
        }
        try startService()
    }

    private func startService() throws {
        guard let configContent else {
            throw startupError("Нет конфигурации")
        }
        do {
            try commandServer!.startOrReloadService(configContent, options: LibboxOverrideOptions())
        } catch {
            throw startupError("start service: \(error.localizedDescription)")
        }
    }

    func stopService() {
        do {
            try commandServer?.closeService()
        } catch {
            NSLog("LitEnergy: stop service: \(error.localizedDescription)")
        }
        platformInterface.reset()
    }

    func reloadService() throws {
        reasserting = true
        defer { reasserting = false }
        try startService()
    }

    override func stopTunnel(with _: NEProviderStopReason) async {
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        // приложение может прислать новый конфиг без переподключения
        guard let config = String(data: messageData, encoding: .utf8), config.contains("\"inbounds\"") else {
            return nil
        }
        configContent = config
        try? config.write(to: savedConfigURL, atomically: true, encoding: .utf8)
        do {
            try reloadService()
            return nil
        } catch {
            return error.localizedDescription.data(using: .utf8)
        }
    }

    override func sleep() async {
        commandServer?.pause()
    }

    override func wake() {
        commandServer?.wake()
    }

    func writeMessage(_ message: String) {
        NSLog("LitEnergy: \(message)")
    }

    private func startupError(_ message: String) -> NSError {
        NSError(domain: "LitEnergy", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
