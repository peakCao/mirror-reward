require 'open3'
require 'tmpdir'
require 'json'

source = File.read(File.join(__dir__, '../engine/Runtime.swift')) + "\n" + File.read(File.join(__dir__, '../engine/ad_watcher.swift'))
target_declaration = source.lines.find { |line| line.start_with?('let maxAds =') }
declarations = source.split('let maxAds =', 2).first
# The permission cases never enter the UI loop, even on the unfixed version.
no_ui = source.sub('while completedAds < maxAds && !watcherControl.isStopped {', 'while false {')
goal_check = 'let maxAds =' + source.split('let maxAds =', 2).last
goal_check = goal_check.sub('var pendingAdCompletion = false', 'var pendingAdCompletion = true')
goal_check = goal_check.gsub('findMirrorWindow()', 'Optional(WindowTarget(wid: 1, bounds: CGRect(x: 0, y: 0, width: 344, height: 764)))')
goal_check = goal_check.gsub('captureAndOCR(wid: win.wid)', 'testFrame()').gsub('clickAt(', 'unexpectedClick(')
frame_type = source.include?('-> [OCRItem]?') ? '[OCRItem]?' : '[OCRItem]'
goal_check = declarations + <<~SWIFT + goal_check
  func testFrame() -> #{frame_type} {
      [OCRItem(text: "恭喜获得第27天免费时长畅听", box: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.04)),
       OCRItem(text: "立即解锁", box: CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.04))]
  }
  func unexpectedClick(screenX: CGFloat, screenY: CGFloat) {
      print("FAIL: clicked after reaching the requested target")
      exit(1)
  }
SWIFT
goal_check += "\nguard completedAds == 1 else { print(\"FAIL: reward not counted\"); exit(1) }\n"
lossless_goal = goal_check.sub('恭喜获得第27天免费时长畅听', '恭喜获得 第3天无损音质').sub('立即解锁', '领取第4日无损音质')

def entry_check(goal_check, label)
  goal_check.sub('var pendingAdCompletion = true', 'var pendingAdCompletion = false')
    .sub('恭喜获得第27天免费时长畅听', '恭喜获得 第3天无损音质')
    .sub('立即解锁', label)
    .sub('print("FAIL: clicked after reaching the requested target")',
         'if completedAds == 0 && screenY > 600 { exit(0) }; print("FAIL: wrong entry or duplicate count")')
end

non_action = entry_check(goal_check, '第4天无损音质')
  .sub('if completedAds == 0 && screenY > 600 { exit(0) }', 'if false { exit(0) }')
  .sub('guard completedAds == 1', 'guard completedAds == 0')

claim_main = 'let maxAds =' + source.split('let maxAds =', 2).last
claim_main = claim_main.sub('var pendingAdCompletion = false', 'var pendingAdCompletion = true')
claim_main = claim_main.gsub('findMirrorWindow()', 'Optional(WindowTarget(wid: 1, bounds: CGRect(x: 0, y: 0, width: 344, height: 764)))')
claim_main = claim_main.gsub('captureAndOCR(wid: win.wid)', 'testFrame()').gsub('clickAt(', 'testClick(')
claim_check = declarations + <<~SWIFT + claim_main
  var frameNumber = 0
  var claimClicks = 0
  var closeClicks = 0
  func testFrame() -> #{frame_type} {
      frameNumber += 1
      if frameNumber > 8 { print("FAIL: flow stalled"); exit(1) }
      if frameNumber == 3 {
          return [OCRItem(text: "20秒后可领奖励", box: CGRect(x: 0.7, y: 0.86, width: 0.2, height: 0.03))]
      }
      let success = OCRItem(text: "领取成功", box: CGRect(x: 0.7, y: 0.86, width: 0.2, height: 0.03))
      if frameNumber == 4 { return [success] }
      return [success,
              OCRItem(text: "坚持退出", box: CGRect(x: 0.4, y: 0.38, width: 0.2, height: 0.03)),
              OCRItem(text: "领取奖励", box: CGRect(x: 0.4, y: 0.44, width: 0.2, height: 0.03))]
  }
  func testClick(screenX: CGFloat, screenY: CGFloat) {
      if screenY > 400 && screenY < 430 {
          guard completedAds == 1 else { print("FAIL: duplicate or missing count"); exit(1) }
          claimClicks += 1
      } else if screenY < 150 {
          closeClicks += 1
      } else {
          print("FAIL: selected exit instead of claim"); exit(1)
      }
  }
SWIFT
claim_check += "\nguard completedAds == 2 && claimClicks == 2 && closeClicks == 1 else { print(\"FAIL: wrong counts or extra ad\"); exit(1) }\n"
missing_claim = claim_check.sub('text: "领取奖励"', 'text: "奖励说明"')
  .sub('guard completedAds == 2 && claimClicks == 2 && closeClicks == 1', 'guard completedAds == 0 && claimClicks == 0 && closeClicks == 0')

live_main = claim_main.sub('var pendingAdCompletion = true', 'var pendingAdCompletion = false')
live_main = live_main.gsub('ProcessInfo.processInfo.systemUptime', 'testNow')
live_check = declarations + <<~SWIFT + live_main
  var frameNumber = 0
  var testNow: TimeInterval = 100
  var liveClicks = 0
  var adClicks = 0
  func testFrame() -> #{frame_type} {
      frameNumber += 1
      if frameNumber > 6 { print("FAIL: live flow stalled"); exit(1) }
      testNow = [100, 110, 134, 136, 137, 138][frameNumber - 1]
      let success = OCRItem(text: "领取成功", box: CGRect(x: 0.7, y: 0.86, width: 0.2, height: 0.03))
      if frameNumber == 1 {
          return [OCRItem(text: "35秒后可领奖励 X", box: CGRect(x: 0.6, y: 0.86, width: 0.3, height: 0.03))]
      }
      if frameNumber < 5 {
          return [OCRItem(text: "更多直播", box: CGRect(x: 0.8, y: 0.83, width: 0.15, height: 0.03)),
                  OCRItem(text: "说点什么...", box: CGRect(x: 0.1, y: 0.05, width: 0.2, height: 0.03)),
                  OCRItem(text: "商品倒计时99秒", box: CGRect(x: 0.2, y: 0.75, width: 0.3, height: 0.03)),
                  OCRItem(text: "X", box: CGRect(x: 0.92, y: 0.865, width: 0.04, height: 0.025))]
      }
      if frameNumber == 5 { return [success] }
      return [success,
              OCRItem(text: "坚持退出", box: CGRect(x: 0.4, y: 0.38, width: 0.2, height: 0.03)),
              OCRItem(text: "领取奖励", box: CGRect(x: 0.4, y: 0.44, width: 0.2, height: 0.03))]
  }
  func testClick(screenX: CGFloat, screenY: CGFloat) {
      guard completedAds == 0 else { print("FAIL: live exit counted as reward"); exit(1) }
      if frameNumber == 4 && screenX > 320 && screenX < 328 && screenY > 86 && screenY < 100 {
          guard !pendingAdCompletion else { print("FAIL: premature completion"); exit(1) }
          liveClicks += 1
      } else if frameNumber == 5 && screenX == 304 && screenY < 150 {
          guard !pendingAdCompletion else { print("FAIL: live exit marked complete"); exit(1) }
          adClicks += 1
      } else { print("FAIL: early or unrelated live click on frame \\(frameNumber)"); exit(1) }
  }
SWIFT
live_check += "\nguard completedAds == 1 && liveClicks == 1 && adClicks == 1 else { print(\"FAIL: incorrect live flow\"); exit(1) }\n"
live_unknown_timer = live_check.sub('var frameNumber = 0', 'var frameNumber = 1')
  .sub('guard completedAds == 1 && liveClicks == 1 && adClicks == 1', 'guard completedAds == 0 && liveClicks == 0 && adClicks == 0')
non_live_page = live_check.sub('text: "更多直播"', 'text: "商家咨询"')
  .sub('text: "说点什么..."', 'text: "发送消息"').sub('text: "X"', 'text: ""')
  .sub('if frameNumber > 6', 'if frameNumber > 20').sub('testNow = [100, 110, 134, 136, 137, 138][frameNumber - 1]', 'testNow = 100 + Double(frameNumber) * 40')
  .sub('if frameNumber < 5', 'if frameNumber > 1')
  .sub('guard completedAds == 1 && liveClicks == 1 && adClicks == 1', 'guard completedAds == 0 && liveClicks == 0 && adClicks == 0')

# Exercise the production click body without posting events to the desktop.
click_body = source[/func clickAt\(.*?(?=\nstruct OCRItem)/m]
click_body = click_body.gsub('requireInputAccess()', '')
  .gsub('if watcherControl.isStopped { return }', '')
  .gsub('continuityApps.first?.activate(options: .activateAllWindows)', '')
  .gsub(/usleep\([^\n]+\)/, '')
  .gsub('CGEvent(source: nil)', 'testCursorEvent()')
  .gsub('CGEvent(mouseEventSource:', 'testMouseEvent(mouseEventSource:')
  .gsub('CGWarpMouseCursorPosition(', 'testWarp(')
  .gsub(/(\w+)\.post\(tap: \.cghidEventTap\)/, 'testPost(\1)')
cursor_check = "import Cocoa\n" + <<~SWIFT + click_body + <<~SWIFT
  var cursor = CGPoint(x: -1250, y: 420)
  var posted: [CGEventType] = []
  var restores = 0
  let failedEvents = CommandLine.arguments.last == "failed-events"
  func testCursorEvent() -> CGEvent? {
      let event = CGEvent(source: nil)
      event?.location = cursor
      return event
  }
  func testMouseEvent(mouseEventSource: CGEventSource?, mouseType: CGEventType, mouseCursorPosition: CGPoint, mouseButton: CGMouseButton) -> CGEvent? {
      if failedEvents && mouseType != .mouseMoved { return nil }
      return CGEvent(mouseEventSource: mouseEventSource, mouseType: mouseType, mouseCursorPosition: mouseCursorPosition, mouseButton: mouseButton)
  }
  func testPost(_ event: CGEvent) {
      cursor = event.location
      posted.append(event.type)
      if event.type != .mouseMoved && cursor != CGPoint(x: 900, y: 300) { exit(1) }
  }
  func testWarp(_ point: CGPoint) {
      if point == CGPoint(x: -1250, y: 420) {
          guard failedEvents || posted.last == .leftMouseUp else { exit(1) }
          restores += 1
      }
      cursor = point
  }
SWIFT
  clickAt(screenX: 900, screenY: 300)
  guard cursor == CGPoint(x: -1250, y: 420), restores == 1 else {
      print("FAIL: cursor was not restored exactly once"); exit(1)
  }
  let buttons = posted.filter { $0 != .mouseMoved }
  guard buttons == (failedEvents ? [] : [.leftMouseDown, .leftMouseUp]) else { exit(1) }
SWIFT

# Replay fresh OCR frames; no scenario may post a real mouse event.
def sequence_check(source, frames, expected_clicks, pending: false, completed: 0)
  declarations, main = source.split('let maxAds =', 2)
  main = 'let maxAds =' + main
  main = main.sub('var pendingAdCompletion = false', "var pendingAdCompletion = #{pending}")
    .gsub('findMirrorWindow()', 'Optional(WindowTarget(wid: 1, bounds: CGRect(x: 0, y: 0, width: 344, height: 764)))')
    .gsub('captureAndOCR(wid: win.wid)', 'testFrame()').gsub('clickAt(', 'testClick(')
    .gsub('ProcessInfo.processInfo.systemUptime', '(1000 + Double(frameNumber) * 40)')
  swift_frames = frames.map do |frame|
    next 'nil' if frame.nil?
    '[' + frame.map { |text, x, y, w, h| "OCRItem(text: #{text.to_json}, box: CGRect(x: #{x}, y: #{y}, width: #{w}, height: #{h}))" }.join(',') + ']'
  end.join(',\n')
  swift_clicks = expected_clicks.map { |x, y| "CGPoint(x: #{x}, y: #{y})" }.join(',')
  declarations + <<~SWIFT + main + <<~SWIFT
    let frames: [[OCRItem]?] = [#{swift_frames.gsub('\\n', "\n")}]
    let expectedClicks: [CGPoint] = [#{swift_clicks}]
    var frameNumber = 0
    var clickCount = 0
    func testFrame() -> [OCRItem]? {
        guard frameNumber < frames.count else { print("FAIL: exceeded frame budget"); exit(1) }
        defer { frameNumber += 1 }
        return frames[frameNumber]
    }
    func testClick(screenX: CGFloat, screenY: CGFloat) {
        guard clickCount < expectedClicks.count else { print("FAIL: unexpected click"); exit(1) }
        let expected = expectedClicks[clickCount]
        guard abs(screenX - expected.x) < 0.01 && abs(screenY - expected.y) < 0.01,
              completedAds == 0 else { print("FAIL: wrong target or premature count"); exit(1) }
        clickCount += 1
    }
  SWIFT
    guard clickCount == expectedClicks.count, frameNumber == frames.count, completedAds == #{completed} else {
        print("FAIL: stopped at frame \\(frameNumber), clicks \\(clickCount), completed \\(completedAds)"); exit(1)
    }
  SWIFT
end

success_frame = [['领取成功', 0.7, 0.86, 0.2, 0.03]]
dialog_frame = success_frame + [['坚持退出', 0.4, 0.38, 0.2, 0.03]]
reward_frame = dialog_frame + [['领取奖励', 0.4, 0.44, 0.2, 0.03]]
interaction_frame = dialog_frame + [['继续互动', 0.4, 0.44, 0.2, 0.03]]
countdown_frame = [['35秒后可领奖励', 0.7, 0.86, 0.2, 0.03]]
live_frame = [['更多直播', 0.8, 0.83, 0.15, 0.03], ['说点什么...', 0.1, 0.05, 0.2, 0.03]]
live_x_frame = live_frame + [['X', 0.92, 0.865, 0.04, 0.025]]
done_frame = [['今日上限', 0.2, 0.4, 0.6, 0.03]]
coin_frame = reward_frame + [['再看1个视频提前得', 0.3, 0.56, 0.4, 0.04]]
four_coin_frame = reward_frame + [['再看 4 个视频', 0.3, 0.60, 0.4, 0.03], ['提前得', 0.3, 0.56, 0.4, 0.03]]
coin_interaction_frame = interaction_frame + [['完成互动，领取金币福利', 0.3, 0.56, 0.4, 0.04]]
member_entry_frame = [['看视频赚金币', 0.3, 0.1, 0.4, 0.03], ['领取第5日无损音质', 0.3, 0.2, 0.4, 0.03]]
cases = {
  'program defaults to 300' => ["import Foundation\n#{target_declaration}\nif maxAds != 300 { exit(1) }", 0, []],
  'program preserves explicit target' => ["import Foundation\n#{target_declaration}\nif maxAds != 7 { exit(1) }", 0, ['7']],
  'capture failure rejects stale image' => [declarations + <<~SWIFT, 0],
    let frame: [OCRItem]? = captureAndOCR(wid: CGWindowID.max)
    guard frame == nil else {
        print("FAIL: failed capture returned a usable OCR frame")
        exit(1)
    }
  SWIFT
  'accessibility denied stops startup' => [no_ui.gsub('AXIsProcessTrusted()', 'false'), 77],
  'event posting denied stops startup' => [no_ui.gsub('CGPreflightPostEventAccess()', 'false'), 77],
  'target reached prevents further clicks' => [goal_check, 0],
  'lossless receipt counts once and stops at target' => [lossless_goal, 0],
  'lossless next-day button starts without recounting receipt' => [entry_check(goal_check, '领取第 4 日无损音质'), 0],
  'lossless video entry containing xiang-di is actionable' => [entry_check(goal_check, '看1个视频 享第3日无损音质'), 0],
  'lossless heading is not an action or a new reward' => [non_action, 0],
  'claim shortcut counts once and does not start beyond target' => [claim_check, 0, '2'],
  'missing claim button never falls back to exit' => [missing_claim, 0, '2'],
  'live room waits for remembered countdown before closing' => [live_check, 0],
  'live fallback waits for countdown and never counts room exit' => [live_check.sub('text: "X"', 'text: ""'), 0],
  'live room without timer stops without clicking' => [live_unknown_timer, 0],
  'live fallback without timer never clicks' => [live_unknown_timer.sub('text: "X"', 'text: ""'), 0],
  'merchant page never uses live close fallback' => [non_live_page, 0],
  'cursor returns to negative-screen origin after mouse up' => [cursor_check, 0],
  'cursor returns even if click event creation fails' => [cursor_check, 0, 'failed-events'],
  'interaction prompt retries 10 times without counting completion' => [sequence_check(source, [interaction_frame] * 11, [[172, 416.38]] * 10, pending: true), 0],
  'interaction and success alternate for 10 rounds without recounting' => [sequence_check(source, [interaction_frame, success_frame] * 10 + [interaction_frame], [[172, 416.38], [304, 95.5]] * 10, pending: true), 0],
  'interaction loop ends on a lossless receipt counted once' => [sequence_check(source, [interaction_frame, success_frame] * 2 + [[['恭喜获得 第3天无损音质', 0.2, 0.3, 0.6, 0.04]]], [[172, 416.38], [304, 95.5]] * 2, completed: 1), 0],
  'interaction loop ends on the completed claim prompt' => [sequence_check(source, [interaction_frame, success_frame] * 2 + [reward_frame], [[172, 416.38], [304, 95.5]] * 2, completed: 1), 0],
  'wake permits exactly 10 clicks' => [sequence_check(source, [[['点击即可使用', 0.2, 0.3, 0.6, 0.04]]] * 11, [[172, 382]] * 10), 0],
  'reward button permits exactly 10 clicks' => [sequence_check(source, [reward_frame] * 11, [[172, 416.38]] * 10), 0],
  'ad close permits exactly 10 clicks' => [sequence_check(source, [success_frame] * 11, [[304, 95.5]] * 10), 0],
  'continue watching permits exactly 10 clicks' => [sequence_check(source, [[['放弃奖励', 0.4, 0.38, 0.2, 0.03], ['继续观看', 0.4, 0.44, 0.2, 0.03]]] * 11, [[172, 416.38]] * 10), 0],
  'next-ad trigger permits exactly 10 clicks' => [sequence_check(source, [[['领取第5日无损音质', 0.4, 0.1, 0.2, 0.03]]] * 11, [[172, 676.14]] * 10), 0],
  'live close permits exactly 10 clicks' => [sequence_check(source, [countdown_frame] + [live_x_frame] * 11, [[323.36, 93.59]] * 10), 0],
  'missing live X uses window-relative fallback' => [sequence_check(source, [countdown_frame, live_frame, done_frame], [[323.36, 91.68]]), 0],
  'live fallback permits exactly 10 clicks' => [sequence_check(source, [countdown_frame] + [live_frame] * 11, [[323.36, 91.68]] * 10), 0],
  'live fallback follows moved and scaled window' => [sequence_check(source, [countdown_frame, live_frame, done_frame], [[-811.968, 310.016]]).sub('CGRect(x: 0, y: 0, width: 344, height: 764)', 'CGRect(x: -1200, y: 200, width: 412.8, height: 916.8)'), 0],
  'live X OCR takes priority when it recovers' => [sequence_check(source, [countdown_frame] + [live_frame] * 4 + [live_x_frame, done_frame], [[323.36, 91.68]] * 4 + [[323.36, 93.59]]), 0],
  'empty live frames never use fallback and stop after 5 misses' => [sequence_check(source, [countdown_frame, live_frame, nil, [], nil, [], nil], [[323.36, 91.68]]), 0],
  'lost live labels never use fallback and stop after 5 misses' => [sequence_check(source, [countdown_frame, live_frame] + [[['内容', 0.2, 0.4, 0.6, 0.03]]] * 5, [[323.36, 91.68]]), 0]
}
cases.merge!({
  'coin offer exits without counting the success label' => [sequence_check(source, [coin_frame, done_frame], [[172, 462.22]], pending: true), 0],
  'coin offer handles split heading and variable video count' => [sequence_check(source, [four_coin_frame, done_frame], [[172, 462.22]]), 0],
  'coin interaction exits instead of continuing interaction' => [sequence_check(source, [coin_interaction_frame, done_frame], [[172, 462.22]], pending: true), 0],
  'coin exit permits exactly 10 clicks without counting' => [sequence_check(source, [coin_frame] * 11, [[172, 462.22]] * 10, pending: true), 0],
  'coin heading temporarily missed does not revert to claiming' => [sequence_check(source, [coin_frame, reward_frame, done_frame], [[172, 462.22]] * 2), 0],
  'coin offer with missing exit never clicks claim' => [sequence_check(source, [coin_frame.reject { |item| item.first == '坚持退出' }], [], pending: true), 0],
  'coin exit reenters a membership entry not a coin entry' => [sequence_check(source, [coin_frame, member_entry_frame, done_frame], [[172, 462.22], [172, 599.74]], pending: true), 0],
  'coin recovery rejects an unlabelled video entry' => [sequence_check(source, [coin_frame] + [[['看视频', 0.3, 0.2, 0.4, 0.03]]] * 6, [[172, 462.22]]), 0],
  'coin exit counts only a subsequent membership receipt' => [sequence_check(source, [coin_frame, [['恭喜获得 第5天会员', 0.2, 0.3, 0.6, 0.04]]], [[172, 462.22]], pending: true, completed: 1), 0],
  'coin receipt beside a membership entry is not a membership reward' => [sequence_check(source, [coin_frame, [['恭喜获得100金币', 0.2, 0.3, 0.6, 0.04]] + member_entry_frame, done_frame], [[172, 462.22], [172, 599.74]], pending: true), 0],
  'coin exit resumes membership advertising and counts its receipt' => [sequence_check(source, [coin_frame, member_entry_frame, countdown_frame, success_frame, [['恭喜获得 第5天会员', 0.2, 0.3, 0.6, 0.04]]], [[172, 462.22], [172, 599.74], [304, 95.5]], pending: true, completed: 1), 0],
  'coin offer over live room takes priority over live X' => [sequence_check(source, [coin_frame + live_x_frame, done_frame], [[172, 462.22]]), 0],
  'coin exit waits for the displayed countdown to finish' => [sequence_check(source, [coin_frame + countdown_frame, coin_frame, done_frame], [[172, 462.22]]), 0],
  'membership-labelled offer is not a coin offer' => [sequence_check(source, [reward_frame + [['再看1个视频提前得会员', 0.3, 0.56, 0.4, 0.04]], done_frame], [[172, 416.38]]), 0],
  'coin text outside the dialog does not override membership claim' => [sequence_check(source, [reward_frame + [['领取会员福利', 0.3, 0.56, 0.4, 0.04], ['金币商城', 0.3, 0.05, 0.4, 0.03]], done_frame], [[172, 416.38]]), 0]
})

# Paid membership ad: benefit badges belong to the product, not reward entry buttons.
paid_ad_frame = [
  ['广告', 0.06, 0.925, 0.08, 0.02],
  ['汽水音乐会员', 0.1, 0.70, 0.8, 0.08],
  ['汽水音乐 SVIP 连续包年', 0.29, 0.225, 0.4, 0.02],
  ['免广告 全景声 音效 铃声', 0.30, 0.202, 0.35, 0.015],
  ['到期自动续费158元/年', 0.1, 0.15, 0.75, 0.02],
  ['立即购买', 0.4, 0.07, 0.2, 0.025]
]
high_countdown = [['22 秒后可领奖励×', 0.7, 0.93, 0.25, 0.02]]
high_success = [['领取成功×', 0.7, 0.93, 0.25, 0.02]]
cases.merge!({
  'paid ad waits for high countdown and only closes after success' => [sequence_check(source, [paid_ad_frame + high_countdown] * 2 + [paid_ad_frame + high_success, reward_frame], [[304, 45.84]], completed: 1), 0],
  'paid ad tolerates missing countdown digits without clicking badges' => [sequence_check(source, [paid_ad_frame + [['秒 后 可 领 奖 励×', 0.7, 0.86, 0.25, 0.02]]] * 7 + [paid_ad_frame + success_frame, reward_frame], [[304, 95.5]], completed: 1), 0],
  'paid ad never clicks badges when countdown OCR is absent' => [sequence_check(source, [paid_ad_frame] * 6, []), 0],
  'paid offer never treats unlock or video sales copy as reward entry' => [sequence_check(source, [paid_ad_frame + [['立即解锁', 0.3, 0.4, 0.4, 0.03], ['看视频了解会员', 0.3, 0.3, 0.4, 0.03]]] * 6, []), 0],
  'bare ad-free benefit is not an entry button' => [sequence_check(source, [[['免广告', 0.3, 0.2, 0.4, 0.03]]] * 6, []), 0],
  'explicit video reward entry remains actionable' => [sequence_check(source, [[['看视频免广告', 0.3, 0.2, 0.4, 0.03]], done_frame], [[172, 599.74]]), 0]
})

cases.select! { |name, _| name.match?(Regexp.new(ENV['TEST_FILTER'])) } if ENV['TEST_FILTER']

failed = 0
launcher = File.read(File.join(__dir__, '../scripts/start.sh'))
count_assignment = launcher.lines.find { |line| line.start_with?('COUNT=') }
[[[], '300'], [['7'], '7']].each do |args, expected|
  output, error, run = Open3.capture3('bash', '-c', "#{count_assignment}\nprintf '%s' \"$COUNT\"", 'check', *args)
  passed = run.success? && output == expected
  puts "#{passed ? 'PASS' : 'FAIL'}: launcher target #{args.empty? ? 'default' : args.first} (#{output}, expected #{expected})"
  failed += 1 unless passed
end
Dir.mktmpdir('ad-watcher-check') do |dir|
  cases.each do |name, (code, expected, target)|
    code = code.gsub(/Thread\.sleep\(forTimeInterval: [^\n]+\)/, '')
    code = code.gsub(/watcherControl\.wait\(seconds: [^\n]+\)/, '')
    code = code.gsub('try watcherControl.start()', '')
    unless name.include?('denied stops startup')
      code = code.gsub(/^requireInputAccess\(\)$/, '')
    end
    binary = File.join(dir, 'check')
    _, error, build = Open3.capture3('swiftc', '-O', '-o', binary, '-', stdin_data: code)
    abort(error) unless build.success?
    output, error, run = Open3.capture3(binary, *Array(target || '1'))
    passed = run.exitstatus == expected
    puts "#{passed ? 'PASS' : 'FAIL'}: #{name} (exit #{run.exitstatus}, expected #{expected})"
    warn(output + error) unless passed
    failed += 1 unless passed
  end
end
exit(failed.zero? ? 0 : 1)
