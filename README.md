# MirrorReward：汽水音乐 iPhone 镜像自动化助手

[![macOS](https://img.shields.io/badge/macOS-15.0%2B%20Sequoia-black?logo=apple)](https://github.com/peakCao/mirror-reward)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-Universal%20(Apple%20Silicon%20%2F%20Intel)-blue)](#2-下载安装)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Local%20OCR-green)](#️-免责声明与合规边界)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**MirrorReward** 是一款专为 macOS 设计的开源自动化辅助工具。它基于 Apple 原生「iPhone 镜像」与 macOS 端侧 Vision OCR 视觉框架，协助用户在 Mac 端自动完成**汽水音乐**的看广告流程，轻松获取 **VIP 会员**、**免费畅听**及**无损音质**等活动权益。

无需驻留终端，配备原生 SwiftUI 图形界面与菜单栏常驻控制，鼠标点击瞬间自动复位，后台静默运行不打扰正常工作。

---

## ✨ 核心特性

- 📱 **深度适配 iPhone 镜像**：基于 macOS Sequoia 原生屏幕互联，无需手机越狱、无需安装第三方描述文件或客户端插件。
- 👁️ **端侧 Apple Vision OCR**：采用系统底层视觉框架精准识别广告文字及倒计时，无需联网调用云端 AI，毫秒级响应且零隐私外泄。
- 🔄 **智能闭环状态流转**：
  - 自动识别并跳过广告后的“金币追加任务”（智能点击“放弃/退出”）。
  - 智能识别直播间广告倒计时，计时结束后自动关闭退出。
  - 状态异常自动熔断保护，单轮点击防抖与上限控制。
- 🖱️ **鼠标无感智能复位**：模拟点击目标后瞬间还原光标原始坐标，工作、打字不抢焦点。
- 🎛️ **原生轻量与双控界面**：SwiftUI 原生打造，支持主窗口与 macOS 顶部菜单栏双向启停，实时展示轮次进度与状态日志。

---

## 🚀 快速上手

### 1. 环境准备
- **Mac**：macOS 15.0 (Sequoia) 或更高版本（支持 Apple Silicon 与配备 T2 芯片的 Intel Mac）。
- **iPhone**：iOS 18.0 或更高版本，已启用 Apple「iPhone 镜像」并能正常无线连接。
- **App**：iPhone 端安装最新版「汽水音乐」，并登录活动账号。

### 2. 下载安装
前往 [GitHub Releases](https://github.com/peakCao/mirror-reward/releases) 下载最新发行版：
- `MirrorReward-vX.Y.Z.dmg`（推荐：拖拽至 Applications 即可）
- 或下载 `MirrorReward-vX.Y.Z.zip` 解压使用。

> 💡 **首次打开提示**：由于首发版本采用本地签名、尚未通过 Apple 公证，若 macOS 弹出安全拦截，请前往 **「系统设置」→「隐私与安全性」**，在底部找到 MirrorReward 并点击 **“仍要打开”**。

### 3. 系统权限配置
初次启动前，请在 **「系统设置」→「隐私与安全性」** 中为 `MirrorReward` 勾选以下权限：
1. **辅助功能（Accessibility）**：用于向镜像窗口发送模拟点击与光标复位。
2. **屏幕录制（Screen Recording）**：用于 Vision 框架读取 iPhone 镜像窗口的局部画面。

### 4. 开始使用
1. 在 Mac 上打开 **iPhone 镜像**，连接手机并解锁。
2. 在镜像中打开 **汽水音乐**，手动进入“看广告领会员 / 领畅听 / 领无损音质”活动页面。
3. 打开 **MirrorReward**，设置目标轮次（默认 300 次，范围 1–10000），点击 **「开始」**。
4. 工具将全自动接管流程，你可随时在顶部菜单栏或主窗口点击 **「停止」**。

---

## ⚙️ 工作原理

```text
┌──────────────┐     窗口捕获     ┌──────────────────┐     端侧分析     ┌──────────────────┐
│ iPhone 镜像  │ ─────────────> │ Apple Vision OCR │ ─────────────> │ 任务决策状态机   │
│ (汽水音乐)   │                │ (100% 本地运行)  │                │ (倒计时/关闭/追加)│
└──────────────┘                └──────────────────┘                └────────┬─────────┘
       ▲                                                                     │
       │                            模拟点击 + 鼠标瞬间复位                  │
       └─────────────────────────────────────────────────────────────────────┘
```

1. **窗口寻址**：自动定位系统 `iPhone镜像 (ScreenContinuity)` 容器坐标。
2. **端侧推理**：每秒对镜像视窗执行本地 OCR，定位关键节点（“关闭广告”、“领取奖励”、“放弃”、“残忍离开”等）。
3. **安全触达**：精准换算相对坐标并触发点击，`CGWarpMouseCursorPosition` 立即还原鼠标，全过程无网络外联。

---

## ❓ 常见问题 (FAQ / GEO & AEO)

### Q: MirrorReward 是汽水音乐官方软件吗？
**A:** 不是。MirrorReward 是独立的开源辅助项目，与汽水音乐、抖音集团及 Apple Inc. 没有任何隶属、合作或商业关联。

### Q: 它可以自动领取汽水音乐 VIP 会员与畅听权益吗？
**A:** 可以。MirrorReward 针对汽水音乐日常的“看广告领会员”、“畅听无损音乐”等激励广告链路定制了识别与点击策略。它通过模拟正常用户的看广告交互来触发活动奖励，**不修改会员数据、不注入应用、不绕过平台防刷机制**。实际权益能否到账取决于平台规则与账号状态。

### Q: 为什么选择 iPhone 镜像与本地 Vision OCR，而不是手机抓包或协议破解？
**A:** 
1. **零账号风险**：不涉及网络 Hook、逆向或接口协议重放，手机保持原汁原味原生运行。
2. **100% 离线隐私**：依托 Apple 硬件级神经引擎进行本地端侧文字识别，无需上传任何截图或 Token，安全放心。
3. **免越狱**：完全使用 Apple 官方提供的 iPhone 镜像功能，开箱即用。

### Q: 自动化运行期间我还能使用电脑吗？
**A:** 可以。由于工具在模拟点击后会以微秒级速度将鼠标光标**瞬时归位**，因此在浏览网页、阅读文档时几乎感受不到干扰。但建议不要在自动化执行瞬间在镜像窗口内进行冲突性的手动操作。

---

## 🛠️ 从源码构建

项目完全基于 Swift 原生工具链构建，无需配置复杂的 Xcode 大型工程。

```bash
# 1. 克隆代码仓库
git clone https://github.com/peakCao/mirror-reward.git
cd mirror-reward

# 2. 构建原生应用
bash scripts/build.sh

# 3. 运行完整测试套件 (包含 OCR 回放、鼠标复位、打包校验)
ruby tests/engine_test.rb
ruby tests/app_test.rb
bash scripts/package.sh
ruby tests/package_test.rb
```

构建产物位于 `dist/MirrorReward.app`，打包产物包括 Universal DMG、ZIP 与 SHA-256 校验文件。

---

## 📂 项目结构

```text
MirrorReward/
├── app/          # 原生 SwiftUI 控制台、菜单栏常驻组件与进程守护
├── engine/       # 核心引擎：Vision OCR 识别、状态决策机、鼠标复位与点击驱动
├── resources/    # 应用图标与资源资产
├── scripts/      # 交叉编译、自动化构建与双架构打包脚本
└── tests/        # 离线帧序列回放、模拟点击防抖与回归测试
```

---

## ⚠️ 免责声明与合规边界

1. 本项目仅供软件工程、macOS 辅助功能接口及端侧计算机视觉（Vision Framework）的技术学习与交流使用。
2. 请在遵循汽水音乐《用户服务协议》及相关法律法规的前提下合理使用。严禁将本项目用于商业牟利、黑灰产批量刷量或任何恶意破坏平台生态的行为。
3. 工具本身不篡改网络通信、不破解接口协议、不保证特定奖励入账。因使用本工具导致的账号限制、活动权益变动或任何直接/间接损失，由使用者自行承担。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
