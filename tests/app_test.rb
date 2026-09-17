require 'open3'
require 'tmpdir'
require 'timeout'

root = File.expand_path('..', __dir__)
Dir.mktmpdir('mirror-reward-test') do |dir|
  source = File.read(File.join(root, 'app/Runner.swift')) + "\n" + <<~'SWIFT'
    var buffer = LineBuffer()
    let input = Data("领取成功\n第二行\n末尾".utf8)
    var output: [String] = []
    for byte in input { output += buffer.append(Data([byte])) }
    output += buffer.append(Data(), finish: true)
    precondition(output == ["领取成功", "第二行", "末尾"])
    let event = try JSONDecoder().decode(EngineEvent.self, from: Data(#"{"event":"progress","completed":2,"target":300}"#.utf8))
    precondition(event.completed == 2 && event.target == 300)
    precondition((try? JSONDecoder().decode(EngineEvent.self, from: Data("ordinary log".utf8))) == nil)
    print("PASS: UTF-8 line buffering and JSON progress")
  SWIFT
  binary = File.join(dir, 'check')
  _, err, build = Open3.capture3('swiftc', '-swift-version', '5', '-o', binary, '-', stdin_data: source)
  abort(err) unless build.success?
  abort('app parsing test failed') unless system(binary)

  source = File.read(File.join(root, 'engine/Runtime.swift')) + "\n" + <<~SWIFT
    setbuf(stdout, nil)
    do { try watcherControl.start() } catch { print("LOCKED"); exit(73) }
    print("READY")
    watcherControl.wait(seconds: 120)
    precondition(watcherControl.isStopped)
    print("STOPPED")
  SWIFT
  _, err, build = Open3.capture3('swiftc', '-o', binary, '-', stdin_data: source)
  abort(err) unless build.success?
  Open3.popen2e(binary) do |stdin, stdout, worker|
    stdin.close
    begin
      Timeout.timeout(10) do
        abort('worker did not start') unless stdout.gets&.strip == 'READY'
        duplicate, _, status = Open3.capture3(binary)
        abort('duplicate worker not rejected') unless status.exitstatus == 73 && duplicate.include?('LOCKED')
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Process.kill('TERM', worker.pid)
        abort('signal did not cancel sleep') unless stdout.gets&.strip == 'STOPPED'
        abort('worker failed') unless worker.value.success?
        abort('stop took too long') unless Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 2
        puts 'PASS: single worker lock and prompt cooperative cancellation'
      end
    ensure
      Process.kill('KILL', worker.pid) if worker.alive?
    end
  end
  Timeout.timeout(5) do
    output, _, status = Open3.capture3({ 'MIRROR_REWARD_PARENT_PID' => '2147483647' }, binary)
    abort('orphan worker did not stop') unless status.success? && output.include?('STOPPED')
    puts 'PASS: missing parent stops the worker'
  end
end

engine = File.join(root, 'dist/MirrorReward.app/Contents/MacOS/ad_watcher')
%w[invalid 0 -1 10001].each do |target|
  _, _, status = Open3.capture3(engine, target)
  abort("invalid target accepted: #{target}") unless status.exitstatus == 64
end
puts 'PASS: invalid CLI targets rejected before any UI action'
