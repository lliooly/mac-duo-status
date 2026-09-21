# 本地签名 helper 可用化设计

## 背景

v2.0.0 的 GitHub DMG 使用未签名构建，主应用可以启动和展示只读状态，但
`SMAppService` 无法稳定注册电源控制 LaunchDaemon。当前 helper 还把调用方
Team ID 固定为 `PM2QH96LXN`。本机 Apple Development 签名经过 `codesign`
验证后的 Team Identifier 也是 `PM2QH96LXN`，但公开 DMG 仍然是 ad hoc 签名，
因此主应用无法通过 helper 的调用方校验。

## 目标

- 让当前 Mac 可以通过 Xcode/本地脚本构建一个带开发签名的可用版本。
- 让电源 helper 信任与自身相同 Team ID 的主应用，而不是依赖仓库中的个人旧值。
- 保留 GitHub Release 的未签名 DMG，明确其为只读分发版本。
- 不引入 Developer ID、公证或付费分发流程。

## 非目标

- 不让未签名 DMG 获得 root helper 能力。
- 不绕过 Gatekeeper、代码签名或 launchd 的系统安全检查。
- 不改变电池、网络、Widget 等现有只读数据能力。
- 不把个人 Team ID、证书私钥或 provisioning profile 提交到仓库。

## 方案

### 1. helper 调用方信任

在 `DuoStatusPowerHelper` 中移除硬编码 Team ID。helper 启动后读取自身的
代码签名信息，取得自身 Team Identifier；收到 XPC 连接时，读取调用方的
bundle identifier 与 Team Identifier，并要求两者分别匹配
`com.shishishi3.mac-duo-status` 和 helper 自身的 Team Identifier。

这样同一开发团队的本地签名构建可以协同工作，换 Team 或换机器时不需要再
修改 Swift 源码；未签名程序仍无法伪装成已授权调用方。

### 2. 本地构建入口

扩展 `script/build_and_run.sh` 的本地构建路径：

- 默认使用 Xcode 自动签名和当前开发团队。
- 允许通过 `DEVELOPMENT_TEAM` 环境变量覆盖团队；未指定时使用当前项目
  的本地开发配置。
- 保持 `xcodebuild` 的 Debug 构建、启动和进程验证流程。
- 构建后校验主应用、helper 和 Widget 的签名 Team Identifier 一致。

Release 打包脚本继续显式关闭代码签名，避免本地签名身份进入公开产物。

### 3. 状态与错误处理

- helper 已注册且 XPC 握手成功：显示“已授权”，启用高级控制。
- 注册失败、签名不一致或 XPC 握手失败：保持只读，显示现有失败状态。
- 不把本地开发签名描述为可公开分发签名；README 增加本地构建与限制说明。

## 数据流

```text
Xcode/本地脚本
    ↓ 自动开发签名
主应用 + Widget + LaunchDaemon helper
    ↓ SMAppService.daemon.register()
launchd 启动 helper
    ↓ XPC
helper 比较主应用 bundle ID 与双方 Team ID
    ↓
ControlCoordinator 暴露电源读写能力
```

## 验收标准

1. 当前本机使用 Apple Development 身份构建成功，且主应用、Widget、helper
   的 Team Identifier 一致。
2. 本地构建启动后点击 `Enable`，helper 状态变为 `Authorized`，不再显示
   “Helper not enabled”。
3. helper 可以读取 Battery/AC 电源模式；在用户确认前不自动修改系统电源设置。
4. 单元测试通过，现有只读状态、Widget 和未签名 Release 打包流程不回归。
5. `git diff --check` 通过，未提交证书、私钥、profile 或本机路径。

## 风险与回退

- 如果当前 Apple Development 账号不允许注册该 LaunchDaemon，应用仍保持只读，
  并给出明确错误；不通过提权脚本绕过系统限制。
- 如果本机已有旧 helper 注册，先通过应用内 Disable 或系统 launchd 清理，
  再重新注册当前构建的 helper。
- 公开 DMG 的行为保持不变；需要高级控制的用户必须从源码使用自己的签名构建。
