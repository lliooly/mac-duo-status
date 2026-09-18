# Duo Status

Duo Status 是一个轻量的 macOS 菜单栏状态聚合工具，用一个组合图标快速展示当前 Mac 的电池、网络和系统健康状态。

## 当前状态

项目已完成 V1 基础状态能力、合并控制版本和能源模式后端的主要实现。菜单栏入口、弹出面板、设置面板、统一状态源、真实系统状态采集、Wi-Fi 控制链路和电源辅助进程均已接入；仍需在目标 Apple silicon 设备上完成硬件场景验收。

产品定位是个人使用、轻量和稳定优先：

- 读取当前 Mac 的本机状态，并在能力可用时执行用户主动发起的本地控制。
- 优先使用 Apple 公开 API。
- 不连接服务器，不同步账号数据。
- 电源控制后端不可用时，明确回退为只读，不伪造成功状态。

## 当前功能

- 菜单栏常驻组合图标。
- 电池状态读取。
- Wi-Fi、有线网络、个人热点和未连接状态读取。
- Wi-Fi 网络扫描、已知网络展示、连接和开关控制。
- Wi-Fi 凭据安全输入；“记住此网络”允许用户选择，默认关闭。
- CPU 使用率、系统负载和系统热状态读取。
- 能源模式读取（Automatic、Low Power、High Power）和辅助进程授权状态展示。
- 电源模式控制入口按设备能力、读回结果和辅助进程状态降级；充电上限仍是独立能力。
- 点击图标查看状态详情。
- 独立设置面板。
- 切换下方四个健康指示点的指标。
- 开机启动、图标外观和弹出面板默认折叠状态设置。
- 简体中文和英文界面，其他语言回退英文。

## 版本边界

| 版本 | 内容 |
| --- | --- |
| 基础状态版本 | 三类状态读取、实时组合图标、弹出面板、设置面板和配置持久化 |
| 合并控制版本 | Wi-Fi 控制、控制状态确认、电源能力模型和可选辅助进程 |
| 能源模式后端 | 通过受信任 helper 固定参数调用 `/usr/bin/pmset`，读取和切换按供电来源保存的模式 |

优先支持 Apple silicon。Intel Mac 不在当前支持范围内。电源写入后端需要在目标设备、签名和授权环境中单独验收；未满足条件时应用保持可用的只读模式。

## 文档

- [产品规格](docs/product-spec.md)
- [架构说明](docs/architecture.md)
- [测试说明](docs/testing.md)
- [合并控制版本设计](docs/superpowers/specs/2026-09-15-merged-control-version-design.md)
- [合并控制版本实现计划](docs/superpowers/plans/2026-09-15-merged-control-version-plan.md)
- [能源模式 pmset 后端设计](docs/superpowers/specs/2026-09-18-energy-mode-pmset-backend-design.md)

## 本地开发

1. 安装完整的 Xcode。
2. 打开 mac-duo-status.xcodeproj。
3. 选择 mac-duo-status Scheme。
4. 在 Apple silicon Mac、macOS 13 或更高版本上运行。

命令行构建需要完整 Xcode 和对应的 macOS SDK。可使用 `xcodebuild -project mac-duo-status.xcodeproj -scheme mac-duo-status -destination 'platform=macOS' build`。

## 隐私和权限

应用只读取和展示当前 Mac 的本机状态；控制操作也只作用于当前 Mac。Wi-Fi 密码不持久化，“记住此网络”默认关闭且由用户主动选择。主应用不以 root 运行，不保存管理员密码或临时授权凭证；辅助进程仅在明确签名和授权后，使用固定参数调用系统内置 `/usr/bin/pmset`。

项目不包含远程监控、iPhone 连接、蜂窝网络状态、用户账号、云同步、进程级 CPU 排名、复杂历史图表或日志系统。

## 许可证

当前仓库尚未包含许可证文件，因此暂不宣称具体的开源许可证。
