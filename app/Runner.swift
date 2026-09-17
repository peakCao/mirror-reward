import AppKit
import SwiftUI

struct EngineEvent: Decodable {
    let event: String
    let completed: Int
    let target: Int
}

// Keep partial UTF-8 bytes until a complete line arrives from the worker.
struct LineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data, finish: Bool = false) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(of: 10) {
            lines.append(String(decoding: pending[..<end], as: UTF8.self))
            pending.removeSubrange(...end)
        }
        if finish && !pending.isEmpty {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines
    }
}

@MainActor
final class Runner: ObservableObject {
    @Published var target = UserDefaults.standard.object(forKey: "target") as? Int ?? 300
    @Published private(set) var running = false
    @Published private(set) var stopping = false
    @Published private(set) var completed = 0
    @Published private(set) var activeTarget = 300
    @Published private(set) var status = "待开始"
    @Published private(set) var logs: [String] = []
    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    @Published private(set) var mirrorOpen = false
    private var process: Process?
    var onStopped: (() -> Void)?

    var validTarget: Bool { (1...10000).contains(target) }
    var ready: Bool { accessibility && screenRecording && mirrorOpen && validTarget }

    func refreshPermissions() {
        accessibility = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        screenRecording = CGPreflightScreenCaptureAccess()
        mirrorOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").isEmpty
    }

    func openPermission(_ pane: String) {
        if pane == "Privacy_Accessibility" {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else {
            _ = CGRequestScreenCaptureAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMirror() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenContinuity") else {
            status = "未找到 iPhone 镜像"
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func start() {
        guard !running else { return }
        refreshPermissions()
        guard ready else { status = "请检查权限、镜像连接及目标数量"; return }
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ad_watcher") else {
            status = "安装不完整：缺少运行程序"
            return
        }
        let child = Process()
        let pipe = Pipe()
        child.executableURL = executable
        child.arguments = [String(target)]
        var environment = ProcessInfo.processInfo.environment
        environment["MIRROR_REWARD_EVENTS"] = "1"
        environment["MIRROR_REWARD_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        child.environment = environment
        child.standardOutput = pipe
        child.standardError = pipe
        do {
            try child.run()
        } catch {
            status = "启动失败：\(error.localizedDescription)"
            return
        }
        UserDefaults.standard.set(target, forKey: "target")
        process = child
        activeTarget = target
        completed = 0
        logs = []
        running = true
        stopping = false
        status = "运行中"
        // Drain output before reporting termination, preserving the final progress event.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let owner = self else { return }
            var buffer = LineBuffer()
            let handle = pipe.fileHandleForReading
            while true {
                let data = handle.availableData
                let lines = buffer.append(data, finish: data.isEmpty)
                DispatchQueue.main.async { owner.receive(lines) }
                if data.isEmpty { break }
            }
            try? handle.close()
            child.waitUntilExit()
            let code = child.terminationStatus
            DispatchQueue.main.async { owner.finish(code: code) }
        }
    }

    func stop() {
        guard let child = process, child.isRunning, !stopping else { return }
        stopping = true
        status = "正在停止"
        child.terminate()
    }

    func clearLog() { logs.removeAll() }

    private func receive(_ lines: [String]) {
        for line in lines where !line.isEmpty {
            if let event = try? JSONDecoder().decode(EngineEvent.self, from: Data(line.utf8)),
               ["progress", "finished"].contains(event.event), event.target == activeTarget,
               (0...activeTarget).contains(event.completed) {
                completed = event.completed
            } else {
                logs.append(line)
            }
        }
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private func finish(code: Int32) {
        status = stopping ? "已停止" : (code != 0 ? "运行失败 (\(code))" : (completed >= activeTarget ? "目标完成" : "已结束，请检查日志"))
        process = nil
        running = false
        stopping = false
        let callback = onStopped
        onStopped = nil
        callback?()
    }
}
