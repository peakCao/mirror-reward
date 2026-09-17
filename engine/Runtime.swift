import Foundation
import Darwin

final class WatcherControl {
    private let condition = NSCondition()
    private var cancelled = false
    private var signals: [DispatchSourceSignal] = []
    private var parentWatch: DispatchSourceTimer?
    private var lockFD: Int32 = -1

    var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func stop() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(seconds: TimeInterval) {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(seconds)
        while !cancelled && Date() < deadline {
            _ = condition.wait(until: deadline)
        }
    }

    func start() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirrorReward", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = open(directory.appendingPathComponent("engine.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            throw NSError(domain: "MirrorReward", code: 73, userInfo: [NSLocalizedDescriptionKey: "已有任务运行，或无法锁定任务文件。"])
        }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { [weak self] in self?.stop() }
            source.resume()
            signals.append(source)
        }
        if let value = ProcessInfo.processInfo.environment["MIRROR_REWARD_PARENT_PID"], let parent = Int32(value) {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in if getppid() != parent { self?.stop() } }
            timer.resume()
            parentWatch = timer
        }
    }
}

let watcherControl = WatcherControl()

func reportProgress(_ completed: Int, target: Int, finished: Bool = false) {
    guard ProcessInfo.processInfo.environment["MIRROR_REWARD_EVENTS"] == "1" else { return }
    let event: [String: Any] = ["event": finished ? "finished" : "progress", "completed": completed, "target": target]
    if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}
