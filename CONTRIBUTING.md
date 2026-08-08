# 贡献指南

感谢你考虑为电池港贡献代码。这个项目包含需要 root 权限的 Helper 和 AppleSMC 写入，因此安全性优先于功能数量。

## 开发环境

- macOS 13 或更高版本
- 完整 Xcode
- Swift 6 工具链

普通界面和业务逻辑可以通过 Swift Package 构建：

```sh
swift test
swift run BatteryHarbor
```

完整 App 与 Helper 请使用 `BatteryHarbor.xcodeproj`。日常 Xcode 开发时，App 和 Helper 必须使用同一个 Development Team 签名。社区 DMG 则由发布脚本使用同一张本地自签名代码签名证书签名两者；私钥和证书备份不得提交到仓库。

## 提交变更前

1. 为修复或功能补充对应测试。
2. 运行 `swift test`。
3. 运行一次 Xcode 无签名构建。
4. 检查没有提交 `.app`、DMG、DerivedData、诊断报告或本机签名产物。
5. 如果界面发生变化，检查浅色/深色模式、中文文本长度、滚动和点击区域。

## Helper 与 SMC 变更

以下变更必须单独说明风险，不能只依赖自动化测试：

- 新增或修改 SMC 键
- 改变写入值、写入顺序或回滚顺序
- 放宽客户端签名、Team ID、Bundle ID 或 root 校验
- 绕过启动后的恢复自检
- 修改暂停充电、主动放电或校准状态机

SMC 写入必须保持固定白名单、写后回读、失败恢复和默认锁定。CI 中禁止安装 Helper 或执行硬件写入。实机验证必须遵循 [Docs/HardwareVerification.md](Docs/HardwareVerification.md)，并由测试者人工确认原值已经恢复。

## 代码与界面约定

- 优先使用 SwiftUI、AppKit 和 SF Symbols。
- 项目自有图标使用原创 SVG；界面中不使用 emoji 作为功能图标。
- 用户可见文本默认使用简体中文，并避免写死会截断的布局宽度。
- 不加入遥测、广告或网络请求，除非先更新隐私说明并明确征得用户同意。
- 不复制闭源应用的代码、资源、商标或专有文案。

## Issue 与 Pull Request

Bug 报告请包含 macOS 版本、Mac 型号、复现步骤及 Helper 自检状态。上传诊断信息前必须移除 Apple ID、序列号、用户名和私人文件路径。

Pull Request 应保持单一目的，并在描述中写明测试方法、硬件风险和回滚方式。
