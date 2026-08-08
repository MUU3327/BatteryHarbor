# 电池港（Battery Harbor）

[简体中文](README.md) | [English](README.en.md)

电池港是一款从零实现的原生 macOS 菜单栏电池管理工具，提供充电上限、暂停充电、临时充满、功率监控、App 能耗排行和计划任务等功能。

> 当前版本为 `0.1.0-alpha.2` 社区技术预览版。底层充电控制会写入 AppleSMC，仅建议能够理解并完成安全自检的用户在测试设备上使用。不同 Mac 型号与 macOS 版本的兼容性仍需继续验证。

## 当前完成状态

| 范围 | 状态 | 说明 |
| --- | --- | --- |
| 电池与功率监控 | 已完成 | 读取电量、温度、健康度、循环次数、电压、电流和实时功率 |
| 菜单栏与主界面 | 已完成 | 简体中文/English、原生图标、统一玻璃材质、四页横向切换动画 |
| App 能耗排行 | 已完成 | 聚合相同宿主 App，支持实时、1 小时和 24 小时视图 |
| 充电控制策略 | 已完成 | 上限、暂停、临时充满、3% 回差、超限自动放电 |
| root Helper | 已完成并在一台 Apple Silicon Mac 上实测 | XPC v3 握手、签名校验、白名单、写后回读、失败回滚和恢复自检 |
| 计划与快捷指令 | 已完成 | 星期/时间计划、执行日志和四个 App Intent |
| 自动保护 | 已完成 | 高温暂停、睡眠暂停、唤醒恢复和后台巡航 |
| 自动化测试 | 32 个单元测试已通过 | CI 只执行普通构建与单元测试，不执行 SMC 写入 |
| 公开发行 | `0.1.0-alpha.2` 本地候选已生成 | 已采用 MIT；社区自签名 DMG 已完成静态验签，上一候选版通过无 Apple ID/无维护者证书的干净账号验证；Developer ID 公证版暂不提供 |

## 主要功能

- 可拖动的充电上限，达到上限后自动暂停充电
- 暂停/恢复充电、临时充至 100%、超出上限时自动放电
- 适配器输入、系统使用和电池流向的实时功率分流
- 每 2 秒采样的实时充放电功率曲线
- 当前耗电 App 排行及最近 24 小时本地历史
- 电池健康度、温度、循环次数、容量、电压和电流详情
- 按星期和时间执行上限、暂停、恢复或临时充满
- 查询状态、设置上限、暂停/恢复和临时充满快捷指令
- 四阶段电池校准、高温保护和睡眠保护
- CSV 历史导出及不含序列号、Apple ID 的诊断报告

## 安全设计

普通 App 进程不会直接写入 SMC。所有控制命令都必须经过签名的 root Helper，并依次满足：

1. 客户端 Bundle ID 和代码签名校验通过；Apple 签名构建要求 App 与 Helper 使用同一 Team，自签名社区构建要求两者使用完全相同的叶证书。无身份的 ad-hoc 构建会被拒绝。
2. Helper 以 root 身份运行，协议版本为 v3。
3. 目标 SMC 键位于固定白名单中，且硬件能力检查通过。
4. Helper 启动后完成一次 `CHTE` 临时写入、回读、原值恢复和再次回读。
5. 每次正式写入均回读验证；失败时按逆序恢复原值。

Helper 或 Mac 重启后会重新锁定控制能力。完整实机步骤见 [充电控制安全自检](Docs/HardwareVerification.md)。

## 系统要求

- macOS 13 或更高版本
- Apple Silicon Mac（当前硬件写入实现的目标平台）
- 本地开发需要完整 Xcode
- Helper 测试要求 App 与 Helper 使用同一个 Personal/Developer Team，或使用同一张本地自签名代码签名证书

Intel Mac、不同 Apple Silicon 代际及更多 macOS 版本尚未形成完整兼容性矩阵。

## 本地构建

### Xcode（推荐）

打开 `BatteryHarbor.xcodeproj`，在 `Signing & Capabilities` 中为 `BatteryHarbor` 与 `BatteryHarborHelper` 选择同一个 Team，然后运行 `BatteryHarbor` scheme。

命令行无签名构建：

```sh
xcodebuild \
  -project BatteryHarbor.xcodeproj \
  -scheme BatteryHarbor \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

无签名构建只能验证编译，不能安装或连接 root Helper。

### Swift Package

```sh
swift run BatteryHarbor
```

`swift run` 适合查看界面和只读监控，但不会生成包含 LaunchDaemon 的完整 App 包，因此不能验证真实充电控制。

## 测试

完整的中英文测试说明见 [Docs/Testing.md](Docs/Testing.md)。

运行 Swift Package 单元测试：

```sh
swift test
```

运行 Xcode 测试：

```sh
xcodebuild \
  -project BatteryHarbor.xcodeproj \
  -scheme BatteryHarbor \
  -destination 'platform=macOS' \
  -derivedDataPath .build/XcodeDerivedData \
  test
```

自动化测试不会安装 Helper，也不会执行任何 SMC 写入。实机控制验证必须由测试者在本机手动完成。

## 数据与隐私

当前源码没有网络请求、遥测或第三方分析 SDK。设置、计划与最近 24 小时的功率/App 能耗样本保存在本机；只有用户主动操作时才会导出 CSV 或诊断报告。详情见 [PRIVACY.md](PRIVACY.md)。

## 项目文档

- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [隐私说明](PRIVACY.md)
- [变更记录](CHANGELOG.md)
- [`0.1.0-alpha.2` 双语发布说明](Docs/ReleaseNotes-0.1.0-alpha.2.md)
- [发布检查清单](Docs/ReleaseChecklist.md)
- [未公证社区 DMG：安装、升级与卸载](Docs/CommunityDMG.md)
- [兼容性矩阵](Docs/Compatibility.md)
- [干净账号发行验证](Docs/CleanEnvironmentTest.md)
- [充电控制安全自检](Docs/HardwareVerification.md)

## 维护者

[MUU3327](https://github.com/MUU3327)

## 许可证

本项目采用 [MIT License](LICENSE)，版权归 `MUU3327` 所有。
