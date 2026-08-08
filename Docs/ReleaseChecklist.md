# GitHub 与发行检查清单

这份清单用于电池港首次公开源码和后续 DMG 发布。任何 GitHub 创建、提交、推送或 Release 操作都应在维护者明确确认后执行。

## 首次公开源码前

- [ ] 最终确认仓库名（建议 `BatteryHarbor`）
- [x] 采用 MIT 许可证，版权署名为 `MUU3327`
- [x] 最终 Bundle ID 已改为 `io.github.muu3327.batteryharbor`
- [x] 将 Xcode 工程中的个人 Team ID 改为可移植配置，避免其他贡献者被绑定到维护者 Team
- [x] App、Helper、LaunchDaemon plist、Mach Service 与 XPC 身份校验已使用同一套最终标识
- [x] 从当前无提交源码执行 `swift test`（32 项通过）
- [x] 执行 arm64 Xcode Release 无签名构建
- [x] 检查 README、隐私说明、安全策略和变更记录
- [x] 检查仓库中没有证书、签名私钥、诊断报告、导出 CSV、个人 Team ID 或个人路径；构建产物已由 `.gitignore` 排除
- [x] 人工检查所有项目图标与资源均为原创项目资源、SF Symbols 或系统控件
- [ ] 建立首个本地 Git 提交后再连接远端；不要把当前无提交工作树直接当作 Release

## 硬件验证

- [ ] 在目标 Apple Silicon Mac 上安装签名的 App 与 Helper
- [ ] 确认 Helper 协议为 v3、PID 有效且以 root 运行
- [ ] 完成 `CHTE` 临时写入、两次回读和原值恢复自检
- [ ] 验证暂停与恢复充电
- [ ] 验证达到上限后的暂停和 3% 回差恢复
- [ ] 验证临时充满结束后恢复原上限
- [ ] 验证超限自动放电关闭与开启两种路径
- [ ] 验证 Helper/App/Mac 重启后的重新锁定行为
- [ ] 退出其他电池管理工具后重复关键测试
- [ ] 记录已验证的 Mac 型号、芯片和 macOS 版本，形成兼容性矩阵

## 源码预览版

- [ ] 创建公开仓库但不上传 DMG
- [ ] 推送 `main` 后确认 CI 通过
- [ ] 检查 Issue 表单和 Pull Request 模板
- [ ] 使用预发布标签，例如 `v0.1.0-alpha.1`
- [ ] 在 Release Notes 中明确技术预览、硬件风险和已验证机型

## DMG 发行

### 未公证社区预览版（不加入 Apple Developer Program）

- [x] App 与 Helper 支持同一张自签名叶证书认证，并拒绝 ad-hoc 身份
- [x] 提供本地 Release 构建、签名、DMG、SHA-256 和静态验签脚本
- [x] 提供中英文安装、升级、卸载和 Gatekeeper 人工批准说明
- [x] 维护者创建并离线保存自签名代码签名证书与私钥备份
- [x] 运行 `Scripts/build-community-release.sh 0.1.0-alpha.2`
- [x] 运行 `Scripts/verify-community-release.sh <DMG>`
- [x] 使用隔离标记的安装副本验证 Gatekeeper“仍要打开”流程
- [x] 在无 Apple ID、无维护者证书的全新临时管理员账号重复 Gatekeeper、Helper、安全自检、暂停/恢复与移除流程
- [x] 验证 `SMAppService` 接受自签名 Helper 的注册、后台项目批准与 XPC v3/root 连接
- [x] 手动完成 `CHTE` 写入、回读、原值恢复和二次回读安全自检
- [x] 手动完成暂停/恢复、充电上限、临时充满和原上限恢复核心回归
- [ ] 将 DMG、`.sha256` 与 manifest 作为 GitHub 预发布附件上传，不提交源码仓库

### Developer ID 公证版（未来可选）

- [ ] 加入 Apple Developer Program 并获得 Developer ID Application 证书
- [ ] Release 构建使用最终 Bundle ID 和版本号
- [ ] App、内嵌 Helper 及所有可执行文件均使用 Developer ID 签名
- [ ] 验证 designated requirement 与 Helper 客户端校验一致
- [ ] 创建只包含 App、Applications 快捷方式和必要说明的 DMG
- [ ] 将 App/DMG 提交 Apple 公证并 stapling
- [ ] 在一台未安装开发证书的 Mac 上验证 Gatekeeper 首次启动
- [ ] 计算并公布 DMG 的 SHA-256
- [ ] 将 DMG 作为 GitHub Release 附件上传，不提交到源码仓库

## 每次发布后

- [ ] 发布标签与 `MARKETING_VERSION` 一致
- [ ] 更新 `CHANGELOG.md`
- [ ] 验证下载链接、校验和与公证状态
- [ ] 保留上一稳定版本，便于回滚
- [ ] 收集兼容性反馈，但不要要求用户公开敏感诊断信息
