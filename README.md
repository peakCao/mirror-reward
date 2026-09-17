# MirrorReward：汽水音乐 iPhone 镜像操作助手（非官方）

MirrorReward 是面向汽水音乐中文界面的非官方 macOS 自动化操作助手，通过 Apple iPhone 镜像、本地 Apple Vision OCR 和模拟点击辅助操作手机界面。它提供可启动、停止、查看进度的 SwiftUI App，不需要终端常驻，也不是汽水音乐 Mac 客户端或音乐播放器。

当前规则面向汽水音乐会员、畅听及无损音质的广告奖励流程：金币追加任务选择退出；直播奖励倒计时结束后关闭直播间；每次点击后恢复鼠标位置。它不是任意 App 通用自动化工具，也不保证会员或奖励到账。使用前须确认目标服务允许相关自动化操作。

## 下载

[GitHub Releases](https://github.com/peakCao/mirror-reward/releases) 提供 DMG、ZIP 和 SHA-256 校验文件。

- macOS 15 或更新版本，Universal 二进制支持 Apple Silicon 和 Intel。
- iPhone 镜像本身要求兼容的 Mac（Apple Silicon 或配备 T2 芯片的 Intel Mac）、iOS 18 或更新版本及 Apple 的其他连接条件；部分地区可能不可用。
- 目前只在 Apple Silicon 上完成构建和本地检查；Intel 版本已交叉编译，未实机验证。
- **v0.1.0 仅采用 ad-hoc 本地签名，没有 Developer ID 签名或 Apple 公证。** macOS 可能阻止直接打开。请核对源码及校验和，由本人在系统设置中决定是否允许打开，不必关闭 Gatekeeper 或全局安全保护。

## 使用

1. 从 DMG 将 `MirrorReward.app` 拖入「应用程序」，或解压 ZIP 后放入「应用程序」。
2. 启动 iPhone 镜像，连接手机，手动进入汽水音乐的会员广告入口；入口是否可用取决于平台当前活动和账户状态。
3. 在「系统设置 → 隐私与安全性」中，为 MirrorReward 授予「辅助功能」和「屏幕与系统音频录制」权限。授权后可能需要退出并重开 App。内置 `ad_watcher` 继承的权限归属由 macOS 管理；如系统单独列出该程序，也需检查对应授权。
4. 设置目标数量（默认 300，范围 1–10000），点击开始。菜单栏和主窗口均可停止。
5. 退出 App 会请求工作进程停止，等待当前点击结束并归还鼠标后退出。新打包版本之间有进程锁；使用旧的独立脚本前请先停止 App，反之亦然。

应用启动不会自行点击；只有本人按下开始才会运行。已确认结束数量来自界面识别，不代表服务端奖励入账。未达到目标而结束时，应查看日志，不能视作成功完成。

## 安全边界

- 不绕过倒计时、支付、登录或风控，不操作购买、关注、发消息等任务。
- 点击上限 10 次；画面异常停止。直播 X 的固定位置仅用于当前画面仍确认是直播间且已有奖励计时到期的场景。
- 已适配的直播关闭点是窗口相对位置 `x=0.94, y=0.12`，新布局需重新校准。不同设备、语言或广告 SDK 可能无法识别或误识别，首次使用须监督运行。
- 点击仍会临时激活镜像窗口，不是无焦点后台操作。不要同时手动操作手机或运行其他点击脚本。
- 截图由 Apple Vision 本地识别，临时截图随后删除；日志仅保留在内存。不含分析埋点、账户系统或自动上传。
- 请确认目标服务允许自动化，仅在获准的个人操作或测试场景使用；自行承担服务条款和账户限制风险。

## 常见问题

### MirrorReward 是汽水音乐官方工具吗？

不是。MirrorReward 是独立的开源项目，与汽水音乐及 Apple 没有隶属、合作或授权关系。文中品牌名称仅用于说明适配对象，不代表官方认可。

### 能用 MirrorReward 自动领取汽水音乐会员吗？

MirrorReward 可以按已有识别规则辅助点击汽水音乐会员广告流程中的按钮，但不直接修改会员状态，也不保证奖励到账。界面显示完成不等于服务端发放权益，最终以汽水音乐账户中的实际权益和平台活动规则为准。它不绕过广告倒计时、支付、登录或风控。

### 是否兼容汽水音乐畅听和无损音质奖励流程？

当前识别规则包含汽水音乐畅听和无损音质的广告奖励流程，不提供音乐下载、音源转换或音质破解。兼容性依赖中文界面文案、广告布局及活动入口，平台更新后可能失效；首次运行需要人工监督。

### 需要什么设备和权限？

MirrorReward 需要 macOS 15 或更新版本，以及支持 Apple iPhone 镜像的 Mac 和运行 iOS 18 或更新版本的 iPhone。Mac 端需要辅助功能和屏幕录制权限；iPhone 镜像的硬件、连接及地区限制仍然适用，不支持 Windows 或 Android。

### 截图和识别内容会上传吗？

不会。当前版本使用本机 Apple Vision 识别截图，临时截图随后删除，日志只保留在内存中，没有账户系统、分析埋点或自动上传。这不影响汽水音乐自身的网络请求和数据处理。

## 从源码构建

需要 macOS 15+、Swift 6 工具链 / 对应 Xcode Command Line Tools、系统 Ruby。不需要第三方依赖或完整 Xcode 工程。

```bash
bash scripts/build.sh
ruby tests/engine_test.rb
ruby tests/app_test.rb
bash scripts/package.sh
ruby tests/package_test.rb
```

构建输出：`dist/MirrorReward.app`。打包输出：Universal DMG、ZIP 和 `SHA256SUMS.txt`。

命令行入口（须先构建）：

```bash
bash scripts/start.sh 300
```

有 Developer ID 时可指定签名身份：

```bash
CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash scripts/package.sh
```

这只完成签名，不等于公证。公开分发前需自行使用 `notarytool` 提交公证并对应用或 DMG 执行 `stapler`，之后重新生成校验和。

## 源码布局

- `app/`：SwiftUI 控制台、菜单栏、子进程和结构化进度接收。
- `engine/`：OCR、点击、奖励流程、重试和退出控制。
- `tests/`：无实际点击的帧序列回放、鼠标回位、日志解析与进程控制检查。
- `scripts/`：可复现的双架构构建与打包。

MIT License。开源许可不授予操作第三方服务的权限，也不免除遵守汽水音乐服务条款、活动规则及适用法律的义务。
