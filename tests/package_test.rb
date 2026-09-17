require 'open3'
require 'tmpdir'

root = File.expand_path('..', __dir__)
version = File.read(File.join(root, 'VERSION')).strip
name = "MirrorReward-#{version}-macos-universal"

def run(*command)
  output, error, status = Open3.capture3(*command)
  abort(output + error) unless status.success?
  output
end

def verify_app(path)
  run('codesign', '--verify', '--deep', '--strict', path)
  %w[MirrorReward ad_watcher].each do |binary|
    architectures = run('lipo', '-archs', File.join(path, 'Contents/MacOS', binary)).split
    abort('missing architecture') unless architectures.sort == %w[arm64 x86_64]
  end
end

Dir.mktmpdir('mirror-reward-package-check') do |dir|
  run('ditto', '-x', '-k', File.join(root, 'dist', "#{name}.zip"), dir)
  verify_app(File.join(dir, 'MirrorReward.app'))
  puts 'PASS: extracted ZIP signature and both architectures'
  mount = File.join(dir, 'mounted')
  Dir.mkdir(mount)
  attached = false
  begin
    run('hdiutil', 'attach', File.join(root, 'dist', "#{name}.dmg"), '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount)
    attached = true
    verify_app(File.join(mount, 'MirrorReward.app'))
    abort('missing Applications link') unless File.readlink(File.join(mount, 'Applications')) == '/Applications'
    puts 'PASS: mounted DMG signature, architectures and installation link'
  ensure
    run('hdiutil', 'detach', mount) if attached
  end
end

Dir.chdir(File.join(root, 'dist')) { run('shasum', '-a', '256', '-c', 'SHA256SUMS.txt') }
puts 'PASS: release checksums'
