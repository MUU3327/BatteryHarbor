# 变更记录

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构。

## [Unreleased]

## [0.1.0-alpha.2] - 2026-08-11

### Added

- 原生 macOS 菜单栏 App、设置窗口与电池详情窗口
- 电池状态、健康信息、功率曲线和 App 能耗排行
- 充电上限、暂停、临时充满和 3% 回差策略
- XPC v3 root Helper、客户端签名校验、SMC 白名单、写后回读与失败恢复
- Helper 启动后的 `CHTE` 写入、回读和原值恢复安全自检
- 计划任务、执行日志、Apple 快捷指令、电池校准和自动保护
- 本机 24 小时历史、CSV 导出及脱敏诊断报告
- 39 个单元测试与 GitHub Actions 普通构建/测试工作流
- MIT 许可证及 GitHub 开源项目文档
- 自签名社区 DMG 构建、校验和静态验签脚本及中英文安装说明

### Changed

- 菜单栏图标改用原生连续电量图标，并区分充电、暂停、保持和放电状态
- 主界面改为跟随系统深浅色的紧凑文字优先布局，保留一层原生玻璃材质与横向标签切换动画
- 充电上限滑块改为珍珠白至深钴蓝渐变，并增加档位间平滑过渡
- 将功率流向和四阶段充电路径诊断放入概览的下方滚动区域
- 降低功率图表与 App 能耗扫描的无效刷新，减少首次展开和鼠标移动时的掉帧
- 功率页以适配器、系统和电池三路流向展示实时功率
- 常规充电上限策略不再启用强制放电，避免电源状态反复切换
- Helper 客户端认证同时支持同 Team 的 Apple 签名构建，以及 App/Helper 叶证书完全一致的自签名社区构建
- 从公开工程配置中移除维护者的 Personal Team ID

### Security

- App 进程不直接执行 SMC 写入
- Helper 或 Mac 重启后重新锁定硬件控制，必须再次完成恢复自检

### Verified

- 自签名社区 DMG 在 MacBook Air（Apple M4，`Mac16,12`）与 macOS 26.6 上通过 Gatekeeper“仍要打开”流程
- 自签名 root Helper 通过 `SMAppService` 注册、XPC v3/root 握手和 `CHTE` 原值恢复安全自检
- 暂停/恢复、达到上限后暂停、临时充满和原上限恢复完成实机回归
- 在无 Apple ID、无维护者证书的全新临时管理员账号完成 Gatekeeper、Helper、安全自检、暂停/恢复与完整移除回归
- `0.1.0-alpha.2` arm64 社区 DMG 通过映像校验、嵌套签名、Bundle ID、共享叶证书和预期 Gatekeeper 行为验证

[Unreleased]: https://github.com/MUU3327/BatteryHarbor/commits/main
[0.1.0-alpha.2]: https://github.com/MUU3327/BatteryHarbor/releases/tag/v0.1.0-alpha.2
