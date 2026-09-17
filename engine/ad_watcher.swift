import Cocoa
import CoreGraphics
import Vision
import Foundation

setbuf(stdout, nil)

struct WindowTarget {
    let wid: CGWindowID
    let bounds: CGRect
}

func findMirrorWindow() -> WindowTarget? {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else { return nil }
    for win in list {
        let owner = win[kCGWindowOwnerName as String] as? String ?? ""
        let name = win[kCGWindowName as String] as? String ?? ""
        if (owner == "iPhone镜像" || owner.contains("ScreenContinuity")) && name == "iPhone镜像" {
            let wid = win[kCGWindowNumber as String] as? Int ?? 0
            guard let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }
            if w > 200 && w < 500 && h > 400 {
                return WindowTarget(wid: CGWindowID(wid), bounds: CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }
    return nil
}

func requireInputAccess() {
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
        fputs("缺少辅助功能/输入事件权限，已停止，不会点击或计数。\n请在系统设置中允许 MirrorReward；命令行启动时允许所用终端。录屏权限不等于点击权限。\n", stderr)
        exit(77)
    }
}

func clickAt(screenX: CGFloat, screenY: CGFloat) {
    if watcherControl.isStopped { return }
    requireInputAccess()
    guard let current = CGEvent(source: nil)?.location else { return }
    defer { CGWarpMouseCursorPosition(current) }
    let continuityApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity")
    continuityApps.first?.activate(options: .activateAllWindows)
    usleep(150_000)

    let target = CGPoint(x: screenX, y: screenY)

    func postMove(to next: CGPoint, from prev: CGPoint) {
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: next, mouseButton: .left) {
            move.setIntegerValueField(.mouseEventDeltaX, value: Int64((next.x - prev.x).rounded()))
            move.setIntegerValueField(.mouseEventDeltaY, value: Int64((next.y - prev.y).rounded()))
            move.post(tap: .cghidEventTap)
        }
    }

    // 1. 平滑带 delta 的光标移动，驱动 iPhone Mirroring 内部虚拟触控光标
    var prev = current
    let steps = 15
    for s in 1...steps {
        let t = CGFloat(s) / CGFloat(steps)
        let next = CGPoint(x: current.x + (target.x - current.x) * t, y: current.y + (target.y - current.y) * t)
        postMove(to: next, from: prev)
        prev = next
        usleep(6_000)
    }
    CGWarpMouseCursorPosition(target)
    usleep(80_000)

    // 2. 局部环形微动，激活 Continuity 触摸指示圈
    var wPrev = target
    for i in 0..<8 {
        let angle = Double(i) * 0.8
        let next = CGPoint(x: target.x + CGFloat(cos(angle) * 8), y: target.y + CGFloat(sin(angle) * 8))
        postMove(to: next, from: wPrev)
        wPrev = next
        usleep(8_000)
    }
    postMove(to: target, from: wPrev)
    CGWarpMouseCursorPosition(target)
    usleep(80_000)

    // 3. 发送标准左键按下与弹起
    if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left),
       let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) {
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
    }
    usleep(200_000)
}

struct OCRItem {
    let text: String
    let box: CGRect
}

func captureAndOCR(wid: CGWindowID) -> [OCRItem]? {
    let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent("iphone-ad-\(UUID().uuidString).png").path
    defer { try? FileManager.default.removeItem(atPath: tmpPath) }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", "\(wid)", tmpPath]
    do { try task.run() } catch { return nil }
    task.waitUntilExit()

    guard task.terminationStatus == 0,
          let img = NSImage(contentsOfFile: tmpPath),
          let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    var items: [OCRItem] = []
    let request = VNRecognizeTextRequest { req, _ in
        guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
        for o in obs {
            if let c = o.topCandidates(1).first {
                items.append(OCRItem(text: c.string, box: o.boundingBox))
            }
        }
    }
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
    do { try handler.perform([request]) } catch { return nil }
    return items
}

let maxClickAttempts = 10
let maxLiveRecognitionFailures = 5
// ponytail: 当前竖屏直播布局的相对关闭位置；布局改变时需重新校准。
let liveCloseFallback = CGPoint(x: 0.94, y: 0.12)

func allowClickAttempt(_ attempts: inout Int, action: String) -> Bool {
    guard attempts < maxClickAttempts else {
        print("停止：\(action)已尝试 \(maxClickAttempts) 次，仍未确认页面变化。")
        return false
    }
    attempts += 1
    print("点击 [\(action)] (\(attempts)/\(maxClickAttempts))")
    return true
}

func hasMembershipBenefit(_ text: String) -> Bool {
    ["会员", "畅听", "无损音质", "免费听", "免广告"].contains { text.contains($0) }
}

let maxAds = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 0) : 300
guard (1...10000).contains(maxAds), CommandLine.arguments.count <= 2 else {
    fputs("目标数量必须是 1 到 10000 的整数。\n", stderr)
    exit(64)
}
do { try watcherControl.start() } catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(73)
}
requireInputAccess()
print("自动看广告已启动，目标: \(maxAds) 个；仅在确认本条结束后计数。")
reportProgress(0, target: maxAds)

var completedAds = 0
var idleTicks = 0
var missingWindowTicks = 0
var closeRetryCount = 0
var rewardRetryCount = 0
var coinExitRetryCount = 0
var returningToMembership = false
var interactionRetryCount = 0
var continueRetryCount = 0
var triggerRetryCount = 0
var wakeRetryCount = 0
var pendingAdCompletion = false
var failedFrames = 0
var adDeadline: TimeInterval? = nil
var liveCloseAttempts = 0
var inLiveRoom = false
var liveRecognitionFailures = 0

while completedAds < maxAds && !watcherControl.isStopped {
    guard let win = findMirrorWindow() else {
        missingWindowTicks += 1
        if missingWindowTicks >= 4 {
            print("🛑 iPhone 镜像窗口已断开，退出！")
            break
        }
        watcherControl.wait(seconds: 1.2)
        continue
    }
    missingWindowTicks = 0

    let items = captureAndOCR(wid: win.wid) ?? []
    if items.isEmpty && !inLiveRoom {
        failedFrames += 1
        print("⚠️ 未取得有效的新画面，不点击、不计数 (\(failedFrames)/3)。")
        if failedFrames >= 3 { break }
        watcherControl.wait(seconds: 1)
        continue
    }
    failedFrames = 0
    let allText = items.map { $0.text }.joined(separator: " ")

    // 0. 锁屏休眠唤醒
    if allText.contains("点击即可使用") || allText.contains("使用 iPhone") || allText.contains("轻点即可使用") {
        if !allowClickAttempt(&wakeRetryCount, action: "唤醒镜像") { break }
        print("💡 检测到休眠，轻触唤醒...")
        clickAt(screenX: win.bounds.origin.x + win.bounds.width * 0.5, screenY: win.bounds.origin.y + win.bounds.height * 0.5)
        watcherControl.wait(seconds: 1.5)
        continue
    }
    wakeRetryCount = 0

    // 1. 断开检测
    let disconnectKeywords = ["已断开", "断开连接", "失去连接", "重新连接", "无法连接", "连接失败", "在 iPhone 上使用", "iPhone 正在使用"]
    if disconnectKeywords.contains(where: { allText.contains($0) }) {
        print("🛑 检测到断开标志，安全退出！")
        break
    }

    // 2. 今日上限检测
    if allText.contains("今日上限") || allText.contains("今日奖励已达") || allText.contains("明日再来") || allText.contains("今日次数已用完") {
        print("🎉 今日广告奖励已达上限，任务圆满完成！累计观看 \(completedAds) 个广告")
        break
    }

    // 保留奖励倒计时，直播间不一定继续显示它；不采纳商品促销计时。
    let now = ProcessInfo.processInfo.systemUptime
    var remainingSeconds: Int? = nil
    for item in items where item.box.origin.y > 0.65 && item.box.origin.y < 0.90 {
        let t = item.text
        if (t.contains("奖励") || t.contains("可领") || t.contains("跳过")),
           let range = t.range(of: "[0-9]{1,3}\\s*(?:秒|[sS])", options: .regularExpression),
           let sec = Int(t[range].filter { $0.isNumber }), sec < 120 {
            remainingSeconds = sec
            adDeadline = now + Double(sec)
            break
        }
    }
    let isLiveRoom = items.contains {
        $0.box.origin.y > 0.78 && $0.box.origin.y < 0.92 &&
        ($0.text.contains("更多直播") || $0.text.contains("人气榜") || $0.text.contains("粉丝"))
    } && items.contains {
        $0.box.origin.y < 0.15 && ($0.text.contains("说点什么") || $0.text.contains("说点啥") || $0.text.contains("聊点什么"))
    }
    let hasCountdown = allText.contains("秒后") || (allText.contains("秒") && (allText.contains("可领") || allText.contains("后")))
    let rewardItem = items.first { $0.text.filter { !$0.isWhitespace } == "领取奖励" }
    let interactionItem = items.first { $0.text.filter { !$0.isWhitespace } == "继续互动" }
    let exitItem = items.first { $0.text.filter { !$0.isWhitespace } == "坚持退出" }
    let dialogText = items.filter {
        $0.box.midX > 0.2 && $0.box.midX < 0.8 && $0.box.midY > 0.25 && $0.box.midY < 0.7
    }.map { $0.text.filter { !$0.isWhitespace } }.joined()
    // 金币图案不会出现在 OCR 中，使用已确认的弹窗标题识别这类加看任务。
    let isCoinOffer = (rewardItem != nil || interactionItem != nil || exitItem != nil) &&
        (dialogText.contains("金币") || (!hasMembershipBenefit(dialogText) &&
            dialogText.range(of: "再看[0-9一二三四五六七八九十]+个视频提前得", options: .regularExpression) != nil))
    let hasAdResult = items.contains {
        $0.box.origin.y > 0.65 && $0.box.origin.y < 0.90 &&
        ($0.text.contains("领取成功") || $0.text.contains("已成功") || ($0.text.contains("跳过") && !hasCountdown))
    }
    let hasRewardReceipt = items.contains {
        $0.text.contains("恭喜获得") && hasMembershipBenefit($0.text) && !$0.text.contains("金币")
    }
    if isCoinOffer || (returningToMembership && (exitItem != nil || rewardItem != nil || interactionItem != nil)) {
        returningToMembership = true
        if hasCountdown {
            watcherControl.wait(seconds: 1)
            continue
        }
        guard let item = exitItem else {
            print("停止：金币弹窗未识别到 [坚持退出]，不领取金币。")
            break
        }
        if !allowClickAttempt(&coinExitRetryCount, action: "坚持退出金币任务，返回会员入口") { break }
        clickAt(screenX: win.bounds.minX + item.box.midX * win.bounds.width,
                screenY: win.bounds.minY + (1 - item.box.midY) * win.bounds.height)
        // 不在金币弹窗计数；返回后仍须看到明确的会员领奖结果。
        pendingAdCompletion = pendingAdCompletion || hasAdResult
        adDeadline = nil
        inLiveRoom = false
        liveCloseAttempts = 0
        liveRecognitionFailures = 0
        closeRetryCount = 0
        interactionRetryCount = 0
        triggerRetryCount = 0
        idleTicks = 0
        watcherControl.wait(seconds: 1.5)
        continue
    }
    if isLiveRoom {
        inLiveRoom = true
    } else if inLiveRoom && (remainingSeconds != nil || hasAdResult || hasRewardReceipt || rewardItem != nil || interactionItem != nil) {
        inLiveRoom = false
        liveCloseAttempts = 0
        liveRecognitionFailures = 0
    }
    // 直播标签或整帧 OCR 暂时缺失时，仍使用直播识别预算。
    if inLiveRoom {
        guard let deadline = adDeadline else {
            print("🛑 已进入直播间，但未获取本条奖励计时，停止，不猜测关闭时间。")
            break
        }
        if now < deadline {
            idleTicks = 0
            watcherControl.wait(seconds: min(deadline - now, 2))
            continue
        }
        let close = items.first {
            $0.box.midX > 0.90 && $0.box.midY > 0.85 && $0.box.midY < 0.90 &&
            ["X", "x", "×", "✕", "✖"].contains($0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard close != nil || isLiveRoom else {
            liveRecognitionFailures += 1
            if liveRecognitionFailures == 1 {
                print("当前画面无法确认直播间，重新获取画面，期间不点击固定位置。")
            }
            if liveRecognitionFailures >= maxLiveRecognitionFailures {
                print("停止：连续 \(maxLiveRecognitionFailures) 次无法确认直播画面。")
                break
            }
            watcherControl.wait(seconds: 1)
            continue
        }
        liveRecognitionFailures = 0
        let action = close == nil ? "直播间右上角 X（固定位置）" : "直播间右上角 X（OCR）"
        if !allowClickAttempt(&liveCloseAttempts, action: action) { break }
        let cx = win.bounds.minX + (close?.box.midX ?? liveCloseFallback.x) * win.bounds.width
        let cy = win.bounds.minY + (close.map { 1 - $0.box.midY } ?? liveCloseFallback.y) * win.bounds.height
        clickAt(screenX: cx, screenY: cy)
        idleTicks = 0
        watcherControl.wait(seconds: 1.5)
        continue
    }

    // 互动未结束，不把顶部的“领取成功”当成本条完成；跨两按钮保留重试预算。
    if let item = interactionItem {
        pendingAdCompletion = false
        if !allowClickAttempt(&interactionRetryCount, action: "继续互动") { break }
        clickAt(screenX: win.bounds.minX + item.box.midX * win.bounds.width,
                screenY: win.bounds.minY + (1 - item.box.midY) * win.bounds.height)
        closeRetryCount = 0
        triggerRetryCount = 0
        idleTicks = 0
        watcherControl.wait(seconds: 1.5)
        continue
    }

    // 3. 领奖弹窗可直达下一条；确认结束后清除 pending，避免重复计数。
    let hasCompletedRewardPrompt = allText.contains("坚持退出") && rewardItem != nil && !hasCountdown && items.contains {
        $0.box.origin.y > 0.65 && $0.box.origin.y < 0.90 && ($0.text.contains("领取成功") || $0.text.contains("已成功"))
    }
    let hasCloseKeywords = allText.contains("领取成功") || allText.contains("已成功") || allText.contains("坚持退出") || allText.contains("放弃奖励")
    if pendingAdCompletion && ((hasRewardReceipt && !hasCloseKeywords) || (!returningToMembership && hasCompletedRewardPrompt)) {
        completedAds += 1
        reportProgress(completedAds, target: maxAds)
        print("✅ 已确认本条广告结束 (\(completedAds)/\(maxAds))")
        pendingAdCompletion = false
        closeRetryCount = 0
        rewardRetryCount = 0
        interactionRetryCount = 0
        continueRetryCount = 0
        triggerRetryCount = 0
        adDeadline = nil
        idleTicks = 0
        if completedAds >= maxAds { break }
    }

    // 4. 非金币弹窗仍直接领奖继续。
    if allText.contains("坚持退出") {
        guard let item = rewardItem else {
            print("🛑 弹窗未识别到 [领取奖励]，停止，不点击 [坚持退出]。")
            break
        }
        if !allowClickAttempt(&rewardRetryCount, action: "领取奖励") { break }
        let cx = win.bounds.origin.x + item.box.midX * win.bounds.width
        let cy = win.bounds.origin.y + (1.0 - item.box.midY) * win.bounds.height
        clickAt(screenX: cx, screenY: cy)
        adDeadline = nil
        idleTicks = 0
        watcherControl.wait(seconds: 1.5)
        continue
    }

    if allText.contains("放弃奖励") {
        guard let item = items.first(where: { $0.text.filter { !$0.isWhitespace } == "继续观看" }) else {
            print("停止：未识别到 [继续观看]，不点击 [放弃奖励]。")
            break
        }
        if !allowClickAttempt(&continueRetryCount, action: "继续观看") { break }
        let cx = win.bounds.origin.x + item.box.midX * win.bounds.width
        let cy = win.bounds.origin.y + (1 - item.box.midY) * win.bounds.height
        clickAt(screenX: cx, screenY: cy)
        watcherControl.wait(seconds: 1.5)
        continue
    }

    // 5. 广告关闭触发（精准对齐右上角 ✕ 物理坐标）
    var closePoint: CGPoint? = nil
    var closeType = ""

    for item in items {
        let t = item.text
        if item.box.origin.y > 0.65 && item.box.origin.y < 0.90 {
            if t.contains("跳过") && !hasCountdown {
                let cx = win.bounds.origin.x + (item.box.origin.x + item.box.size.width / 2.0) * win.bounds.width
                let cy = win.bounds.origin.y + (1.0 - (item.box.origin.y + item.box.size.height / 2.0)) * win.bounds.height
                closePoint = CGPoint(x: cx, y: cy)
                closeType = "跳过"
                break
            } else if t.contains("领取成功") || t.contains("已成功") || (t.contains("可领奖励") && !hasCountdown) {
                // 右上角胶囊关闭点严格对应到 win.bounds.width - 40.0
                let rx = win.bounds.origin.x + win.bounds.width - 40.0
                let cy = win.bounds.origin.y + (1.0 - (item.box.origin.y + item.box.size.height / 2.0)) * win.bounds.height
                closePoint = CGPoint(x: rx, y: cy)
                closeType = "领奖关闭✕"
                break
            } else if (t.contains("✕") || t.contains("×") || t.contains("X") || t.contains("x")) && item.box.origin.x > 0.70 && !hasCountdown {
                let cx = win.bounds.origin.x + (item.box.origin.x + item.box.size.width / 2.0) * win.bounds.width
                let cy = win.bounds.origin.y + (1.0 - (item.box.origin.y + item.box.size.height / 2.0)) * win.bounds.height
                closePoint = CGPoint(x: cx, y: cy)
                closeType = "右上角✕"
                break
            }
        }
    }

    if let pt = closePoint {
        rewardRetryCount = 0
        triggerRetryCount = 0
        if !allowClickAttempt(&closeRetryCount, action: closeType) { break }
        clickAt(screenX: pt.x, screenY: pt.y)
        pendingAdCompletion = true
        idleTicks = 0
        watcherControl.wait(seconds: 1.5)
        continue
    }

    // 6. 倒计时智能休眠 (排除顶部 5G/时间等状态栏)
    if let sec = remainingSeconds {
        closeRetryCount = 0
        rewardRetryCount = 0
        interactionRetryCount = 0
        continueRetryCount = 0
        triggerRetryCount = 0
        if sec > 4 {
            let fastSleep = Double(sec - 2)
            print("⏳ 广告剩余 \(sec) 秒，快进等待 \(Int(fastSleep)) 秒后抢关...")
            watcherControl.wait(seconds: fastSleep)
        } else {
            watcherControl.wait(seconds: 0.5)
        }
        idleTicks = 0
        continue
    }

    // 7. 主界面触发下一个广告按钮 (优先识别底部操作按钮)
    var triggerItem: OCRItem? = nil
    for item in items {
        let t = item.text
        let compactText = t.filter { !$0.isWhitespace }
        if compactText.contains("金币") { continue }
        if returningToMembership && !hasMembershipBenefit(compactText) { continue }
        if compactText.range(of: "^(领取第[0-9]+[日天]无损音质|看[0-9]+个视频享第[0-9]+[日天]无损音质)$", options: .regularExpression) != nil {
            triggerItem = item
            break
        }
        if t.contains("提前得") || t.contains("已领取") || t.contains("回复") || t.contains("享第") || t.contains("条") { continue }
        if t.contains("看1个视频") || t.contains("看视频") || (t.contains("看") && t.contains("视频")) || t.contains("点击观看") || t.contains("观看视频") || t.contains("提前领") || t.contains("再看一个") || t.contains("免费听") || t.contains("免广告") || t.contains("解锁") || (t == "福利" && item.box.origin.y < 0.15) {
            triggerItem = item
            if item.box.origin.y < 0.35 { break }
        }
    }

    if let trig = triggerItem {
        if !allowClickAttempt(&triggerRetryCount, action: trig.text) { break }
        let cx = win.bounds.origin.x + (trig.box.origin.x + trig.box.size.width / 2.0) * win.bounds.width
        let cy = win.bounds.origin.y + (1.0 - (trig.box.origin.y + trig.box.size.height / 2.0)) * win.bounds.height
        print("👉 轻触启动下一个广告: [\(trig.text)]")
        clickAt(screenX: cx, screenY: cy)
        if returningToMembership {
            pendingAdCompletion = false
            returningToMembership = false
            coinExitRetryCount = 0
        }
        adDeadline = nil
        idleTicks = 0
        watcherControl.wait(seconds: 2.5)
        continue
    }

    // 8. 兜底保护
    idleTicks += 1
    if idleTicks >= 6 {
        print("🛑 未识别到可确认的操作，停止，不再盲点右上角。")
        break
    }

    watcherControl.wait(seconds: 0.8)
}

print("任务结束，已确认结束 \(completedAds)/\(maxAds) 个广告；未验证服务端奖励入账。")
reportProgress(completedAds, target: maxAds, finished: true)
