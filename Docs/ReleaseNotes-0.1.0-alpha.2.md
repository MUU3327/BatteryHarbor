# 电池港 0.1.0-alpha.2 / Battery Harbor 0.1.0-alpha.2

> 社区技术预览 / Community Technical Preview

[中文](#中文) | [English](#english)

## 中文

`0.1.0-alpha.2` 是电池港准备首次公开发布的社区候选版本。本版本延续已经完成实机验证的充电控制与安全架构，并集中改善亮色壁纸、默认账户和高透明度环境下的界面可读性。

### 本版变化

- 使用 macOS 26 原生 SwiftUI `glassEffect` 构建导航、卡片和交互控件
- 使用 AppKit `NSVisualEffectView` 与 `behindWindow` 实现窗口级磨砂背景采样
- 加强卡片描边、内侧高光、阴影和内容分区，同时保留背景透射
- 设置页与菜单栏弹窗统一为同一套 Liquid Glass 视觉语言
- 保留“减少透明度”辅助功能的实体背景回退
- 修正设置窗口可能在其他 App 后方打开的问题

### 下载文件

- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.dmg`
- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.dmg.sha256`
- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.txt`

DMG SHA-256：

```text
20be7507f1ba5ed56a9259f5e1735e4147d8aef490473346bc90819210693d9d
```

### 安装与安全

该 DMG 使用项目自签名证书，**未经 Apple Developer ID 签名和公证**。首次打开需要前往“系统设置 → 隐私与安全性”点击“仍要打开”。不要关闭 Gatekeeper 或 SIP。

在启用充电控制前，必须安装 Helper，并由本人完成 `CHTE` 临时写入、回读、原值恢复和二次回读安全自检。详细步骤见 [社区 DMG 安装说明](CommunityDMG.md) 和 [硬件安全自检](HardwareVerification.md)。

### 验证状态

- 32 项单元测试全部通过
- arm64 Release 构建通过
- DMG/APFS 校验通过
- App 与 Helper 嵌套签名通过
- Bundle ID 与 Helper ID 验证通过
- App 与 Helper 共享自签名叶证书验证通过
- Gatekeeper 拒绝未经公证构建属于预期行为

充电暂停/恢复、充电上限、临时充满与原上限恢复已在同一控制代码和 Helper 上完成实机验证；`alpha.2` 相对上一候选版的变化集中在界面层。

## English

`0.1.0-alpha.2` is the community candidate for Battery Harbor's first public release. It retains the charging-control and safety architecture already exercised on real hardware and focuses on legibility over bright wallpapers, default user accounts, and highly translucent backgrounds.

### Changes

- Native SwiftUI `glassEffect` for navigation, cards, and interactive controls on macOS 26
- Window-level frosted backdrop sampling with AppKit `NSVisualEffectView` and `behindWindow`
- Stronger card outlines, inner highlights, shadows, and content separation while retaining backdrop transmission
- One consistent Liquid Glass language across the menu popover and Settings window
- Solid-surface fallback when Reduce Transparency is enabled
- More reliable Settings-window foreground activation

### Downloads

- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.dmg`
- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.dmg.sha256`
- `BatteryHarbor-0.1.0-alpha.2-macos-arm64-unnotarized.txt`

DMG SHA-256:

```text
20be7507f1ba5ed56a9259f5e1735e4147d8aef490473346bc90819210693d9d
```

### Installation and safety

This DMG uses the project's self-signed certificate and is **not signed with Apple Developer ID or notarized by Apple**. On first launch, open System Settings > Privacy & Security and select Open Anyway. Never disable Gatekeeper or SIP.

Before enabling charge control, install the Helper and personally complete the `CHTE` temporary write, read-back, original-value restoration, and second read-back safety self-test. See [Community DMG installation](CommunityDMG.en.md) and [hardware safety verification](HardwareVerification.md).

### Verification status

- All 32 unit tests passed
- arm64 Release build passed
- DMG/APFS checksum validation passed
- Nested App and Helper signatures passed
- App and Helper bundle identifiers passed
- Shared self-signed leaf certificate verification passed
- Gatekeeper rejection is expected because the build is not notarized

Pause/resume charging, charge-limit stopping, temporary full charge, and restoration of the previous limit were exercised on real hardware with the same control code and Helper. Changes from the previous candidate are concentrated in the interface layer.
