# Duo Status 能源模式控制设计

## 文档信息

- 产品：Duo Status
- 仓库：mac-duo-status
- 日期：2026-09-18
- 状态：已批准，已实现；待目标设备写入验收
- 范围：实现截图所示的 macOS Battery「Energy Mode」能力

本文档只覆盖能源模式读取与切换。电池电量、电源来源等基础状态已经由现有
`BatteryProvider` 负责；充电上限属于独立能力，本次不扩大为新的实现目标。

## 1. 背景与目标

Apple 的 Battery 菜单会根据当前供电来源展示 Energy Mode，并允许用户在支持的
设备上选择 Automatic、Low Power 或 High Power。电池供电和电源适配器供电可以
分别保存模式。

本次目标：

- 在 Duo Status 中读取电池和电源适配器两套能源模式。
- 在当前设备能力允许时，从控制界面切换三种模式。
- 让写入结果与 Apple Battery 菜单及系统设置保持一致。
- 写入后通过真实系统读回确认，不能使用乐观更新。
- 辅助进程不可用、设备不支持或系统输出无法解析时，保持安全的只读体验。
- 不链接私有 Framework，不直接修改系统偏好 plist，不执行任意用户命令。

## 2. 调查结论

### 2.1 Apple 公开 API 的边界

Foundation 的 `ProcessInfo.isLowPowerModeEnabled` 只能读取当前是否处于 Low Power
Mode，并可以通过 `NSProcessInfoPowerStateDidChange` 接收状态变化通知。它不能
直接读取或写入 Automatic、High Power，也不能读取电池与适配器的两套配置。

Apple 官方文档确认 macOS Ventura 及更高版本支持按「On battery」和
「On power adapter」分别设置 Energy Mode；High Power 是否出现取决于具体机型。

参考：

- [ProcessInfo.isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled?changes=_9)
- [About Power Modes on your Mac](https://support.apple.com/en-us/101613)

因此，不能只用 Foundation API 复刻截图中的完整能力。当前实现中把
`isLowPowerModeEnabled == false` 映射为 Automatic 也不可靠，因为它可能实际是
Automatic，也可能是 High Power。

### 2.2 `pmset` 的可行性

`/usr/bin/pmset` 是 macOS 内置的电源管理命令。当前开发机上的只读检查结果如下：

- `pmset -g cap` 列出 `lowpowermode` 和 `highpowermode` 能力。
- `pmset -g custom` 能读取每个供电来源的 `powermode` 值。
- 修改命令需要 root 权限。
- 没有执行任何实际修改；本次只进行了只读查询和无权限语法探测。

已知实现约定为：

| 值 | 模式 |
| --- | --- |
| `0` | Automatic |
| `1` | Low Power |
| `2` | High Power |

供电来源参数使用 `-b` 表示电池，`-c` 表示电源适配器。支持 High Power 的设备
优先使用 `powermode`；只有 Low Power 能力的旧设备使用 `lowpowermode`，此时
High Power 不应出现在 UI 中。

`powermode` 相关参数没有在当前 `pmset` 手册中完整公开，因此它不是稳定的
Apple SDK 合同，而是系统内置命令的未完整文档化接口。本项目不直接链接私有
Framework，而是把该命令限制在受信任的 root 辅助进程中，并通过能力探测和回读
保护变化风险。

### 2.3 开源实现参考

[PowerMode](https://github.com/sakesalverda/PowerMode/) 使用辅助进程调用
`/usr/bin/pmset`，并对白名单中的供电来源、模式键和值进行校验。
[nix-darwin 的实现说明](https://github.com/dryvist/nix-darwin/blob/develop/docs/MACOS-LLM-PERFORMANCE-TUNING.md)
也记录了 `powermode` 的三档映射和写入后的回读校验。

这些实现证明该路线在实际 macOS 设备上可行，但不能替代 Apple 对公开 SDK 的
兼容性承诺。因此，后端必须允许按设备和系统版本降级。

## 3. 方案选择

采用「现有受信任 LaunchDaemon + 固定参数调用 `pmset`」方案：

```text
SwiftUI UI
    ↓
ControlCoordinator
    ↓
PowerHelperClient（类型化 XPC）
    ↓
DuoStatusPowerHelper（受信任 LaunchDaemon）
    ↓
PMSetPowerBackend
    ↓
/usr/bin/pmset（固定参数，不经过 shell）
```

不采用以下方案：

- 直接调用 `IOKitPrivate`、`IOPMLibPrivate` 或其他私有 Framework。
- 直接读写 `/Library/Preferences/SystemConfiguration` 下的电源 plist。
- 在主应用中请求管理员密码并执行 `sudo`。
- 接入第三方二进制作为运行时依赖。

第三方开源仓库只作为行为和兼容性参考，不复制其代码或引入其运行时依赖。

## 4. 领域模型与能力语义

### 4.1 现有模型的调整

保留现有 `PowerMode`、`PowerSourceScope`、`PowerPolicyStatus` 和
`PowerCapabilities`，调整其数据来源：

- `batteryMode`：来自 `pmset -g custom` 的 Battery Power 区块。
- `adapterMode`：来自 `pmset -g custom` 的 AC Power 区块。
- `activeMode`：来自 `pmset -g` 当前生效区块；必要时根据当前供电来源选择
  Battery 或 AC 配置。
- `activeMode` 在辅助进程无法读回且 Low Power 未开启时保持 `nil`，不能伪造为
  Automatic。
- `supportedPowerModes` 根据 `pmset -g cap` 和可解析的配置键生成。
- `energyModeScopes` 只包含能够读取对应配置区块的供电来源。

### 4.2 能力降级

| 条件 | 能源模式行为 |
| --- | --- |
| 发现 `powermode` 且包含 High Power 能力 | 显示并允许三种模式 |
| 只有 `lowpowermode` | 只显示 Automatic 和 Low Power |
| 能读取但辅助进程未授权 | 显示只读状态和授权入口 |
| 辅助进程不可用 | 回退到公开 Low Power 读取，其他模式显示不可确认 |
| 输出缺失或值无法解析 | 标记暂不可用，不执行写入 |

Charge Limit 继续沿用现有独立能力状态，不与能源模式能力互相推断。

## 5. 辅助进程后端

### 5.1 `PMSetPowerBackend`

在 `DuoStatusPowerHelper` 中实现真实的 `PowerBackend`：

- 读取能力时执行固定的 `pmset -g cap`。
- 读取模式时执行固定的 `pmset -g custom`，必要时额外执行 `pmset -g`。
- 写入时只允许以下参数组合：
  - 供电来源：`-b`、`-c`。
  - 模式键：`powermode`、`lowpowermode`。
  - 值：`0`、`1`、`2`，其中 `lowpowermode` 不接受 `2`。
- 使用 `Process` 的参数数组调用 `/usr/bin/pmset`，禁止 `sh -c`、字符串拼接
  命令或用户可控路径。
- 写入进程异常退出、超时或返回 stderr 时，映射为稳定的后端错误。
- 同一辅助进程内串行执行电源写入，避免两个设置请求同时覆盖彼此。

### 5.2 读取解析

解析器按区块识别 `Battery Power:` 和 `AC Power:`，只接受完整的整数值。未知
键、未知模式值、重复区块和缺失区块都转为不可用状态，不使用最近一次值冒充
当前系统状态。

解析 `pmset -g` 的当前生效模式时，优先读取 `powermode`；旧设备只存在
`lowpowermode` 时，只返回 Automatic 或 Low Power。

### 5.3 XPC 边界

现有 XPC 协议继续只暴露结构化的能力、读取和写入方法。主应用不接收原始命令
字符串，也不接收管理员密码。辅助进程继续使用现有签名客户端校验，只接受
`com.shishishi3.mac-duo-status` 和当前 Team ID 的主应用连接。

## 6. 控制流程

```text
用户选择模式
    ↓
ControlCoordinator 检查 pending 状态和能力
    ↓
PowerHelperClient 发起类型化 XPC 请求
    ↓
PMSetPowerBackend 执行固定 pmset 参数
    ↓
PowerHelperClient 读取目标作用域
    ↓
SystemStatusStore.refreshNowAndWait()
    ↓
快照确认目标模式
    ↓
成功 / writeUnconfirmed / helperUnavailable
```

所有写入继续使用现有 `pending`、`succeeded` 和 `failed` 状态。写入失败或读回
不一致时，不修改 UI 的已确认选择，并向用户显示错误或未确认状态。

## 7. UI 设计

### 7.1 Battery 区域

保留现有电量和供电来源行，在其下显示当前能源模式。模式未知时显示「暂不可用」
或「无法确认」，不能显示 Automatic。

### 7.2 PowerControlView

将现有两个菜单式 Picker 调整为接近截图的原生模式列表：

- 顶部显示当前作用域：电池或电源适配器。
- 默认选择当前实际供电来源；用户可以切换作用域，以分别设置两套策略。
- 每个可用模式使用独立行、系统图标和选中标记。
- 当前设备不支持的模式不显示。
- 写入期间禁用模式行，保留返回操作。
- 辅助进程未授权时显示授权入口，不显示可写控件。
- 辅助进程不可用时显示只读模式，并提供打开系统 Battery 设置的入口。

### 7.3 系统设置回退

新增打开 Battery 设置的入口，按顺序尝试稳定的系统设置 URL，全部失败时打开
系统设置主窗口。该入口只作为后端不可用时的回退，不承担状态读取。

## 8. 错误处理与安全约束

- 不把 `/usr/bin/pmset` 的完整 stderr 直接展示给用户；只映射为现有
  `ControlError` 或新的稳定错误。
- 不在日志中记录用户路径、密码或任意命令字符串。
- 不因辅助进程失败阻塞主应用启动。
- `pmset` 能力缺失时，主应用仍保持 Battery、Network 和 System Health 的只读
  能力。
- 不自动修改两个供电来源；用户选择哪个作用域，就只写入对应的 `-b` 或 `-c`。
- 不自动恢复旧模式，不在应用退出时改写系统设置。

## 9. 测试与验收

### 9.1 纯逻辑测试

- `0/1/2` 与三种 `PowerMode` 的映射。
- `powermode` 和 `lowpowermode` 输出解析。
- Battery Power、AC Power 区块解析。
- 缺失、重复、未知值和非整数输出的降级。
- 只有 Low Power 能力时不暴露 High Power。
- 无 helper 读取时，不把 `false` 映射成 Automatic。

### 9.2 控制层测试

- 不支持的作用域或模式不会发起 XPC 写入。
- 写入后读回一致才进入 succeeded。
- 读回不一致进入 writeUnconfirmed。
- 同时触发两个能源模式写入时，第二个请求被 pending 保护。
- 辅助进程不可用时主应用保持可启动和只读。

### 9.3 目标设备验收

在支持 High Power 的 Apple silicon MacBook 上验证：

1. Battery 供电下切换三种模式，并在 Apple Battery 菜单确认结果。
2. 电源适配器供电下切换三种模式，并确认不会改写 Battery 配置。
3. 插拔电源后，Duo Status 的当前模式和作用域同步变化。
4. 注销或未安装辅助进程时，UI 正确降级。
5. 不支持 High Power 的设备只显示 Automatic 和 Low Power。

## 10. 实施范围与交付顺序

1. 添加 `PMSetPowerBackend` 及固定参数执行器。
2. 接通 XPC 能力和读取结果，修正 `activeMode` 的误判。
3. 修改 `PowerControlView` 和 Battery 区域的降级显示。
4. 增加 Battery 系统设置回退入口。
5. 补充领域、控制层和 UI 测试。
6. 更新 `README.md`、`docs/architecture.md` 和 `docs/testing.md` 的能力边界。
7. 在目标 Apple silicon 设备上进行真实写入与回读验收。

## 11. 明确不做的事情

- 不调用私有 Framework。
- 不直接读写系统电源 plist。
- 不引入第三方运行时依赖。
- 不在本次实现自动能源策略。
- 不在本次实现新的 Charge Limit 后端。
- 不为实现能源模式创建 worktree；继续使用当前工作区和 `main` 分支。
