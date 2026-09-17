import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runner: Runner?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runner = runner, runner.running else { return .terminateNow }
        runner.onStopped = { sender.reply(toApplicationShouldTerminate: true) }
        runner.stop()
        return .terminateLater
    }
}

@main
struct MirrorRewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var runner = Runner()

    var body: some Scene {
        Window("MirrorReward", id: "main") {
            ControlView(runner: runner)
                .onAppear { delegate.runner = runner; runner.refreshPermissions() }
        }
        .defaultSize(width: 580, height: 630)
        .commands {
            CommandGroup(after: .appInfo) {
                Link("GitHub", destination: URL(string: "https://github.com/peakCao/mirror-reward")!)
            }
        }
        MenuBarExtra("MirrorReward", systemImage: runner.running ? "play.circle.fill" : "iphone") {
            MenuContent(runner: runner)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var runner: Runner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(runner.status) · \(runner.completed)/\(runner.activeTarget)")
        Button("打开控制台") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("开始", systemImage: "play.fill") { runner.start() }.disabled(runner.running)
        Button("停止", systemImage: "stop.fill") { runner.stop() }.disabled(!runner.running || runner.stopping)
        Divider()
        Button("退出 MirrorReward") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct ControlView: View {
    @ObservedObject var runner: Runner
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MirrorReward").font(.title2.bold())
                    Text(runner.status).font(.subheadline).foregroundStyle(runner.running ? .green : .secondary)
                }
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("目标数量")
                TextField("1–10000", value: $runner.target, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 88)
                    .accessibilityLabel("目标数量").disabled(runner.running)
                Stepper("目标数量", value: $runner.target, in: 1...10000, step: 10)
                    .labelsHidden().fixedSize().disabled(runner.running)
                Spacer()
                Button("开始", systemImage: "play.fill") { runner.start() }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(runner.running || !runner.ready)
                Button("停止", systemImage: "stop.fill") { runner.stop() }
                    .disabled(!runner.running || runner.stopping)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("已确认结束").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(runner.completed) / \(runner.running ? runner.activeTarget : max(runner.target, 1))")
                        .monospacedDigit()
                }
                ProgressView(value: Double(runner.completed), total: Double(max(runner.activeTarget, 1))).tint(.green)
            }
            Divider()
            VStack(spacing: 10) {
                permissionRow("辅助功能", ready: runner.accessibility, symbol: "hand.point.up.left") {
                    runner.openPermission("Privacy_Accessibility")
                }
                permissionRow("屏幕录制", ready: runner.screenRecording, symbol: "record.circle") {
                    runner.openPermission("Privacy_ScreenCapture")
                }
                permissionRow("iPhone 镜像", ready: runner.mirrorOpen, symbol: "iphone") { runner.openMirror() }
            }
            Divider()
            HStack {
                Text("运行日志").font(.headline)
                Spacer()
                Button { runner.clearLog() } label: { Image(systemName: "trash") }
                    .help("清空日志").accessibilityLabel("清空日志").disabled(runner.logs.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.logs.isEmpty ? "暂无记录" : runner.logs.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: runner.logs) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .frame(minHeight: 140)
        }
        .padding(22)
        .frame(minWidth: 540, minHeight: 570)
        .onReceive(timer) { _ in runner.refreshPermissions() }
    }

    private func permissionRow(_ title: String, ready: Bool, symbol: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ready ? .green : .orange)
                .accessibilityLabel(ready ? "已就绪" : "未就绪")
            Button(action: action) { Image(systemName: title == "iPhone 镜像" ? "arrow.up.forward.app" : "gearshape") }
                .help(title == "iPhone 镜像" ? "打开 iPhone 镜像" : "打开\(title)设置")
                .accessibilityLabel(title == "iPhone 镜像" ? "打开 iPhone 镜像" : "打开\(title)设置")
        }
    }
}
