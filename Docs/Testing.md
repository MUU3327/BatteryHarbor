# 测试指南 / Testing Guide

[中文](#中文) | [English](#english)

## 中文

### 自动化测试

```sh
swift test
```

当前测试覆盖充电策略、3% 回差、临时充满、计划触发、校准状态机、功率平衡、能耗历史、Helper 协议编码以及 SMC 写入事务的回滚逻辑。自动化测试使用模拟状态，不会安装 Helper，也不会写入真实 SMC。

### 界面与双语检查

1. 打开“设置 → 通用 → 界面语言”。
2. 分别选择“简体中文”和“English”。
3. 检查主面板的概览、功率、App、计划四页，以及设置的六个页面。
4. 检查长文本、滚动区域、按钮点击范围和计划日志。
5. 系统窗口标题和快捷指令元数据若未立即更新，请退出并重新打开 App。

### 硬件控制

真实充电控制不能由 CI 自动测试。必须使用同一 Team 或同一张本地自签名代码签名证书签名 App 与 Helper，并严格按照 [HardwareVerification.md](HardwareVerification.md) 手动完成安装、连接、自检、写入、回读和恢复验证。

## English

### Automated tests

```sh
swift test
```

The current suite covers charge policy, 3% hysteresis, temporary full charge, schedule triggering, the calibration state machine, power balance, energy history, Helper protocol encoding, and rollback behavior for SMC write transactions. Automated tests use simulated state. They do not install the Helper or write to real SMC hardware.

### UI and localization checks

1. Open **Settings → General → Interface Language**.
2. Test both **简体中文** and **English**.
3. Inspect all four dashboard pages—Overview, Power, App, and Schedule—and all six Settings pages.
4. Check long text, scrolling, button hit areas, and schedule logs.
5. If system window titles or Shortcuts metadata do not update immediately, quit and reopen the app.

### Hardware control

Real charge control must not run in CI. Sign the App and Helper with the same Team or the same local self-signed code-signing certificate, then follow [HardwareVerification.md](HardwareVerification.md) to manually verify installation, connection, self-test, write, read-back, and restoration behavior.
