# 电池港 0.1.0-alpha.1 / Battery Harbor 0.1.0-alpha.1

> 技术预览 / Technical Preview

[中文](#中文) | [English](#english)

## 中文

这是电池港首个开源技术预览候选版本。电池港是一款原生 macOS 菜单栏电池养护工具，包含低层 AppleSMC 充电控制。请先阅读安全提示和兼容性矩阵；未经安全自检，不要启用正式充电控制。

### 主要功能

- 可拖动充电上限、3% 回差、暂停/恢复充电
- 临时充至 100%，结束后恢复原上限
- 可选的超限自动放电（实验功能，默认建议关闭）
- 适配器、系统与电池三路实时功率流向及历史曲线
- 当前、1 小时与 24 小时 App 能耗排行
- 电池健康度、温度、循环次数、容量、电压和电流详情
- 星期/时间计划、执行日志和四个 Apple 快捷指令动作
- 高温、睡眠与唤醒保护
- 简体中文与 English 双语界面

### 下载文件

- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.dmg`
- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.dmg.sha256`
- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.txt`

DMG SHA-256：

```text
786fc89c3c0eb59812a86c003417104bb4c76f02af4ed7b7445a7da3167cb010
```

### 安装与安全

该 DMG 使用项目自签名证书，**未经 Apple Developer ID 签名和公证**。首次打开需要前往“系统设置 → 隐私与安全性”点击“仍要打开”。不要关闭 Gatekeeper 或 SIP。

安装 Helper 后，必须由本人完成 `CHTE` 临时写入、回读、原值恢复和二次回读安全自检。App 与 Helper 使用相同叶证书；ad-hoc 或证书不匹配的客户端不能连接 root Helper。

详细步骤见：

- [社区 DMG 安装、升级与卸载](CommunityDMG.md)
- [充电控制安全自检](HardwareVerification.md)
- [兼容性矩阵](Compatibility.md)

### 已验证环境

- MacBook Air `Mac16,12`
- Apple M4
- macOS 26.6 (`25G72`)
- 无 Apple ID、无维护者证书的干净临时管理员账号

已验证 Gatekeeper“仍要打开”、自签名 `SMAppService` root Helper、XPC v3 握手、安全自检、暂停/恢复、上限暂停、临时充满、原上限恢复和 Helper 移除。

### 已知限制

- 仅提供 Apple Silicon `arm64` 构建；Intel Mac 未验证。
- 未经 Apple 公证，普通用户需要人工批准首次启动。
- 兼容性矩阵目前只包含一台 M4 MacBook Air。
- 恢复充电后，macOS 可能延迟几十秒到约一分钟恢复实际电池输入。
- 超限自动放电仍为实验功能，首个预览版建议保持关闭。

## English

This is the first open-source technical-preview candidate of Battery Harbor, a native macOS menu bar battery-care utility with low-level AppleSMC charging control. Read the safety guidance and compatibility matrix first. Do not enable production charge control before completing the safety self-test.

### Highlights

- Draggable charge limit, 3% hysteresis, and pause/resume charging
- Temporary charge to 100% with restoration of the previous limit
- Optional discharge above the limit (experimental; keep disabled by default)
- Live adapter, system, and battery power flow with history charts
- Live, 1-hour, and 24-hour per-app energy ranking
- Battery health, temperature, cycle count, capacity, voltage, and current details
- Weekday/time schedules, execution logs, and four Apple Shortcuts actions
- Temperature, sleep, and wake protection
- Simplified Chinese and English interface

### Downloads

- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.dmg`
- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.dmg.sha256`
- `BatteryHarbor-0.1.0-alpha.1-macos-arm64-unnotarized.txt`

DMG SHA-256:

```text
786fc89c3c0eb59812a86c003417104bb4c76f02af4ed7b7445a7da3167cb010
```

### Installation and safety

The DMG uses the project's self-signed certificate and is **not signed with Apple Developer ID or notarized by Apple**. On first launch, open System Settings > Privacy & Security and select Open Anyway. Never disable Gatekeeper or SIP.

After installing the Helper, the user must personally complete the `CHTE` temporary write, read-back, original-value restore, and second read-back safety self-test. The App and Helper share the same leaf certificate; ad-hoc or certificate-mismatched clients cannot connect to the root Helper.

Detailed guidance:

- [Community DMG installation, upgrade, and removal](CommunityDMG.en.md)
- [Hardware control safety verification](HardwareVerification.md)
- [Compatibility matrix](Compatibility.md)

### Verified environment

- MacBook Air `Mac16,12`
- Apple M4
- macOS 26.6 (`25G72`)
- Clean temporary administrator account with no Apple ID or maintainer certificate

Verified flows include Gatekeeper Open Anyway, the self-signed `SMAppService` root Helper, XPC v3 handshake, safety self-test, pause/resume, limit stop, temporary full charge, previous-limit restoration, and Helper removal.

### Known limitations

- Apple Silicon `arm64` only; Intel Macs are unverified.
- The build is not notarized and requires manual first-launch approval.
- The compatibility matrix currently contains one M4 MacBook Air.
- macOS may take tens of seconds or about a minute to restore actual battery input after charging is allowed again.
- Discharge above the limit remains experimental and should stay disabled in the first preview.
