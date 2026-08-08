# 兼容性矩阵 / Compatibility Matrix

[中文](#中文) | [English](#english)

## 中文

以下结果只代表维护者实际完成的测试组合，不表示同系列所有机型或 macOS 版本均兼容。

| 机型 | 芯片 | macOS | 只读监控 | 社区 DMG | root Helper | 恢复自检 | 核心充电控制 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MacBook Air `Mac16,12` | Apple M4 | 26.6 (`25G72`) | 通过 | Gatekeeper“仍要打开”通过 | 自签名 XPC v3/root 握手通过 | `CHTE` 写入、回读、恢复通过 | 暂停/恢复、上限暂停、临时充满及原上限恢复通过 |

说明：

- 社区 DMG 使用 `Battery Harbor Open Source Release` 自签名证书，未经 Apple 公证；另在无 Apple ID、无维护者证书的全新临时管理员账号完成 Gatekeeper、Helper、安全自检、暂停/恢复与移除验证。
- `root Helper` 通过 `SMAppService` 注册；App 与 Helper 使用完全相同的叶证书。
- Intel Mac、其他 Apple Silicon 机型及其他 macOS 版本尚未验证。
- 兼容性反馈不得包含序列号、Apple ID、硬件 UUID 或未脱敏的用户路径。

## English

These results cover only combinations manually tested by the maintainer. They do not imply compatibility with every Mac in the same family or every macOS release.

| Mac | Chip | macOS | Read-only monitoring | Community DMG | Root Helper | Restore self-test | Core charge control |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MacBook Air `Mac16,12` | Apple M4 | 26.6 (`25G72`) | Passed | Gatekeeper Open Anyway passed | Self-signed XPC v3/root handshake passed | `CHTE` write, read-back, and restore passed | Pause/resume, limit stop, temporary full charge, and limit restoration passed |

Notes:

- The community DMG uses the self-signed `Battery Harbor Open Source Release` certificate and is not notarized by Apple. A fresh temporary administrator account with no Apple ID or maintainer certificate also passed Gatekeeper, Helper, safety self-test, pause/resume, and removal verification.
- The root Helper is registered through `SMAppService`; the App and Helper share the exact same leaf certificate.
- Intel Macs, other Apple Silicon models, and other macOS releases remain unverified.
- Compatibility reports must not include serial numbers, Apple IDs, hardware UUIDs, or unredacted user paths.
