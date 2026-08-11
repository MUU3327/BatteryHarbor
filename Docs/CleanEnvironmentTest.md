# 干净账号发行验证 / Clean-Account Release Verification

[中文](#中文) | [English](#english)

## 中文

这项测试用于验证未安装维护者签名证书的新用户，能否通过 Gatekeeper 人工批准并使用自签名 root Helper。测试账号中不要导入 `Battery Harbor Open Source Release` 证书或 `.p12` 私钥备份。

### 安装与 Gatekeeper

1. 使用一个临时 macOS 管理员账号登录，不登录 Apple ID，不导入任何开发或发布证书。
2. 在 Finder 中打开 `/Users/Shared/BatteryHarbor-0.1-clean-test.dmg`。
3. 将 `Battery Harbor.app` 拖入 `/Applications`。
4. 从“应用程序”打开电池港。若被阻止，前往“系统设置 → 隐私与安全性”，点击“仍要打开”并再次确认。
5. 确认菜单栏图标和主界面可以正常显示。

### Helper 与安全自检

1. 打开“设置 → 充电”，点击“安装控制模块”。
2. 若需要批准，前往“系统设置 → 通用 → 登录项与扩展”批准电池港后台控制模块，然后返回并刷新。
3. 点击“测试连接”，确认显示：
   - `安全握手成功（root）`
   - 协议 `v3` 和有效 PID
   - 硬件写入“已启用”
   - 恢复自检“尚未执行”
4. 连接电源，关闭“超出上限时自动放电”，由本人点击“开始安全自检”。
5. 确认出现“写入、回读和恢复验证已通过”，且恢复证据的首尾值完全相同。
6. 如果任一步失败，停止测试并截图；不要连续重试，不要测试正式控制命令。

### 只做一次暂停/恢复

1. 将充电上限设为 `100%`，保持自动放电关闭。
2. 点击“暂停充电”，确认适配器仍连接且电池输入降至接近 `0 W`。
3. 点击“恢复充电”。高电量时 macOS 可能延迟几十秒到约一分钟恢复实际电池输入。

### 清理测试账号

1. 保持上限 `100%`、自动放电关闭并允许充电。
2. 在“设置 → 充电”点击“重新锁定硬件控制”，再点击“移除模块”。
3. 确认 Helper 不再显示“已启用”，然后退出电池港。
4. 将 `/Applications/Battery Harbor.app` 移到废纸篓。
5. 注销临时账号并返回维护者账号。确认结果已记录后，可以删除临时账号及其个人文件夹。

## English

This test verifies that a new user without the maintainer's signing certificate can approve the app through Gatekeeper and use the self-signed root Helper. Do not import the `Battery Harbor Open Source Release` certificate or its `.p12` private-key backup into the test account.

### Install and Gatekeeper

1. Sign in to a temporary macOS administrator account. Do not sign in with an Apple ID or import any development or release certificate.
2. In Finder, open `/Users/Shared/BatteryHarbor-0.1-clean-test.dmg`.
3. Drag `Battery Harbor.app` to `/Applications`.
4. Open Battery Harbor from Applications. If macOS blocks it, go to System Settings > Privacy & Security, click Open Anyway, and confirm again.
5. Confirm that the menu bar icon and main interface appear normally.

### Helper and safety self-test

1. Open Settings > Charging and select Install Helper.
2. If approval is required, approve the Battery Harbor background control module in System Settings > General > Login Items & Extensions, then return and refresh.
3. Select Test Connection and confirm:
   - Secure handshake succeeded as root
   - Protocol v3 with a valid PID
   - Hardware writes enabled
   - Restore self-test not yet run
4. Connect power, keep automatic discharge disabled, and personally start the safety self-test.
5. Confirm that write, read-back, and restore verification passed, with identical first and last values in the evidence.
6. If anything fails, stop and take a screenshot. Do not retry repeatedly or test production control commands.

### One pause/resume cycle

1. Set the charge limit to 100% and keep automatic discharge disabled.
2. Pause charging. Confirm that the adapter remains connected while battery input falls near 0 W.
3. Resume charging. At a high state of charge, macOS may take tens of seconds or about a minute to restore actual battery input.

### Clean up the test account

1. Leave the limit at 100%, automatic discharge disabled, and charging allowed.
2. In Settings > Charging, relock hardware control and remove the Helper.
3. Confirm that the Helper is no longer enabled, then quit Battery Harbor.
4. Move `/Applications/Battery Harbor.app` to the Trash.
5. Log out of the temporary account and return to the maintainer account. After recording the result, the temporary account and its home folder may be deleted.
