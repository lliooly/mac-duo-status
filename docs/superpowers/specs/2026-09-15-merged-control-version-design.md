# Duo Status V1.1 + V2 合并控制能力设计

> 历史说明：本文档中的充电上限设计已由
> `2026-09-18-remove-charge-limit-design.md` 取消；其余内容仍作为实现依据。

## 文档信息

- 产品：Duo Status
- 仓库：mac-duo-status
- 日期：2026-09-15
- 基线：V1.0.0
- 状态：设计已确认，待创建实现计划

本文档描述在 V1 基础上合并实现 Wi-Fi 控制、能源模式、充电上限和可选特权辅助进程的设计。本文档是实现前的设计约束，不代表相关代码已经存在。

## 1. 已确认的设计决策

### 1.1 版本策略

V1.1 与 V2 合并为一个后续控制能力版本，包含：

- Wi-Fi 开关、扫描和网络切换。
- 开放网络、WEP、WPA/WPA2/WPA3 Personal、Enterprise、隐藏网络和 CoreWLAN 可识别的其他安全类型。
- 已知网络和当前扫描网络的分组展示。
- 能源模式读取与可用时的修改。
- 充电上限读取与可用时的修改。
- 能力探测、授权状态、失败降级和写入后回读确认。

### 1.2 混合权限策略

- 现有只读 Provider 保持为主状态链路。
- 新增独立控制层，UI 不直接调用 CoreWLAN、IOKit 或辅助进程。
- Wi-Fi 控制在主应用内通过 CoreWLAN 执行。
- 能源模式和充电上限使用公开读取能力；写入能力通过可选的签名辅助进程提供。
- 辅助进程按需注册，不在应用启动时默认安装或请求权限。
- 主应用永远不以 root 身份运行。

### 1.3 凭据策略

- Wi-Fi 密码、Enterprise 密码和临时授权凭据不写入 UserDefaults。
- Duo Status 不自行保存 Wi-Fi 密码。
- Enterprise 私钥只通过系统钥匙串中的身份引用使用，不复制私钥。
- “记住此网络”是连接时的单次选择，默认关闭。
- 未勾选时发起连接，但不由 Duo Status 主动写入或修改系统已知网络列表；macOS 已有的系统记忆策略仍由系统负责。
- 勾选时，连接成功后才尝试将网络加入 macOS 的已知网络配置。
- 记住网络失败不能回滚已经成功的连接，UI 应显示“已连接，未能记住网络”。

### 1.4 UI 策略

根弹出面板继续负责状态摘要。Wi-Fi 和高级电源操作进入同一弹窗内的子面板，不把根面板扩展成完整设置页。

Wi-Fi 子面板遵循系统 Wi-Fi 菜单的交互逻辑：

```text
Wi-Fi                         [开关]

Personal Hotspots
Known Networks
Other Networks >
Wi-Fi Settings…
```

个人热点只有在系统明确确认时才分组展示，不根据 SSID 名称猜测。

## 2. 平台边界

### 2.1 Wi-Fi

macOS 使用 Core WLAN 进行扫描、关联、断开和接口电源控制。`CWWiFiClient` 提供的 `CWInterface` 对象用于避免直接创建接口对象导致的沙盒问题。

参考：

- [Core WLAN](https://developer.apple.com/documentation/CoreWLAN)
- [CWInterface](https://developer.apple.com/documentation/corewlan/cwinterface?language=objc)
- [associate(to:password:)](https://developer.apple.com/documentation/corewlan/cwinterface/associate%28to%3Apassword%3A%29)
- [Enterprise association](https://developer.apple.com/documentation/corewlan/cwinterface/associate%28toenterprisenetwork%3Aidentity%3Ausername%3Apassword%3A%29)

CoreWLAN 的 `CWSecurity` 类型作为能力探测依据，包括 Open、WEP、Dynamic WEP、WPA/WPA2/WPA3 Personal、WPA/WPA2/WPA3 Enterprise、WPA3 Transition、OWE 和 Unknown。网络模型保存支持的安全类型集合，而不是只保存一个安全类型。

### 2.2 能源模式

公开 Foundation 能力主要用于读取当前低电量模式和接收电源状态变化通知。当前状态不能假设存在公开写入接口。

能源模式模型分别保存电池和电源适配器两种作用域：

- Automatic。
- Low Power。
- High Power。

能源模式是否可用取决于系统版本、机型和当前电源条件。

参考：[ProcessInfo.isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled?changes=_9)、[About Power Modes on your Mac](https://support.apple.com/en-us/101613)

### 2.3 充电上限

Apple 当前的 Charge Limit 需要 macOS Tahoe 26.4 或更高版本，并且需要 Apple silicon。允许范围为 80% 至 100%。

Charge Limit 是系统认为“充满”的目标，不是瞬时电池百分比硬限制；系统仍可能偶尔充到 100% 以校准电量。

参考：[Optimized Battery Charging and Charge Limit on Mac](https://support.apple.com/en-au/102338)

应用部署目标仍保持 macOS 13，但能力探测必须在运行时根据系统版本、架构、机型和实际后端结果决定是否展示写入控件。

### 2.4 辅助进程

macOS 13 及更高版本使用 `SMAppService` 管理应用包内的 LaunchDaemon。辅助进程必须经过用户批准后才可启动。

参考：[SMAppService](https://developer.apple.com/documentation/ServiceManagement/SMAppService?changes=la&language=objc)、[SMAppService.register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)

## 3. 目标架构

```text
UI
 ├─ SystemStatusStore       // 只读状态快照
 ├─ PreferencesStore        // 长期偏好
 └─ ControlCoordinator       // 操作编排和临时操作状态
       ├─ CapabilityManager
       ├─ NetworkControlProvider
       ├─ PowerPolicyProvider
       └─ PowerHelperClient
                              │
                              └─ NSXPCConnection
                                  DuoStatusPowerHelper
                                      └─ PowerBackend
```

### 3.1 SystemStatusStore

SystemStatusStore 继续是菜单栏图标、弹出面板和设置面板共享的唯一读取状态源。

新增职责：

- 保存 `PowerPolicyStatus`。
- 在控制操作完成后重新读取完整快照。
- 不保存操作密码和 XPC 临时对象。
- 不直接发起写操作。

### 3.2 ControlCoordinator

ControlCoordinator 运行在 `MainActor`，负责：

- 串行化同一类操作。
- 记录 `idle`、`pending`、`succeeded` 和 `failed` 状态。
- 管理扫描结果的生命周期和 `scanToken`。
- 防止过期网络对象被重新使用。
- 将底层错误映射为用户可理解的错误。
- 触发 SystemStatusStore 刷新并等待回读确认。

Wi-Fi 操作和电源操作可以分别串行，但同一领域内同一时刻只允许一个写操作。

## 4. 领域模型和协议

### 4.1 能力和操作状态

```swift
enum CapabilityState: Equatable, Sendable {
    case unsupported
    case readOnly
    case available
    case authorizationRequired
    case temporarilyUnavailable
}

enum ControlOperationState: Equatable, Sendable {
    case idle
    case pending
    case succeeded
    case failed(ControlError)
}

`ControlError` 为应用内错误值，至少包含 `networkNotFound`、`authenticationFailed`、`unsupportedSecurity`、`authorizationRequired`、`helperUnavailable`、`invalidChargeLimit`、`operationTimeout`、`writeUnconfirmed` 和 `cancelled`。
```

统一错误至少包含：

```text
networkNotFound
authenticationFailed
unsupportedSecurity
authorizationRequired
helperUnavailable
invalidChargeLimit
operationTimeout
writeUnconfirmed
cancelled
```

### 4.2 Wi-Fi 模型

`WiFiSecurity` 是对 CoreWLAN `CWSecurity` 的值类型映射，至少包含 `open`、`wep`、`dynamicWEP`、`personal`、`enterprise`、`owe` 和 `unknown`，并保留 WPA/WPA2/WPA3 的具体能力信息。

`HotspotConfirmation` 至少包含 `confirmed`、`notConfirmed` 和 `unavailable` 三种状态。只有 `confirmed` 才能进入 Personal Hotspots 分组。

```swift
struct WiFiNetworkCandidate: Identifiable, Sendable {
    let id: String
    let interfaceName: String
    let ssidData: Data
    let displayName: String?
    let bssid: String?
    let supportedSecurity: Set<WiFiSecurity>
    let rssi: Int?
    let isHidden: Bool
    let isKnown: Bool
    let hotspotConfirmation: HotspotConfirmation
    let scanToken: UUID
}

enum WiFiCredential: Sendable {
    case none
    case passphrase(String)
    case enterprise(
        username: String?,
        password: String?,
        identityReference: KeychainIdentityReference?
    )
}

protocol NetworkControlProviding: Sendable {
    func scan(includeHidden: Bool) async throws -> [WiFiNetworkCandidate]
    func setWiFiEnabled(_ enabled: Bool) async throws
    func connect(
        to target: WiFiNetworkCandidate,
        credential: WiFiCredential?,
        remember: Bool
    ) async throws
}
```

`CWNetwork` 不跨并发边界传给 UI 或 Coordinator。Provider 在 CoreWLAN 线程/actor 内将它转换为值类型模型。

扫描结果按照以下规则合并：

- 已知网络来自 macOS 的 `CWNetworkProfile`。
- 当前扫描网络来自 `scanForNetworks`。
- 同一 SSID 使用 `ssidData` 合并，而不是依赖显示字符串。
- 同一 SSID 有多个 BSSID 时，列表默认显示信号最强项，并保留具体 BSSID 供用户展开选择。
- 已知但当前不可见的网络显示为置灰状态，并标记“未发现”。
- 隐藏网络使用手动 SSID 加 `includeHidden` 扫描；匹配不到时返回 `networkNotFound`。
- 未被系统明确确认的热点不进入 Personal Hotspots 分组。

### 4.3 电源模型

```swift
enum PowerMode: String, Sendable {
    case automatic
    case lowPower
    case highPower
}

enum PowerSourceScope: String, Sendable {
    case battery
    case powerAdapter
}

struct PowerPolicyStatus: Equatable, Sendable {
    let availability: DataAvailability
    let activeMode: PowerMode?
    let batteryMode: PowerMode?
    let adapterMode: PowerMode?
    let chargeLimit: Int?
    let chargeLimitCapability: CapabilityState
    let helperStatus: HelperStatus
}

`PowerCapabilities` 至少包含能源模式的可用作用域、Charge Limit 的允许值集合、是否需要辅助进程以及当前辅助进程状态。

protocol PowerPolicyProviding: Sendable {
    func read() async -> PowerPolicyStatus
}

protocol PowerControlProviding: Sendable {
    func capabilities() async -> PowerCapabilities
    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws
    func setChargeLimit(_ percent: Int) async throws
}
```

充电上限必须满足 `80...100`。UI 初始显示当前系统值，不主动修改；实际允许值仍以能力探测返回结果为准。

### 4.4 辅助进程状态

```swift
enum HelperStatus: Equatable, Sendable {
    case notInstalled
    case requiresApproval
    case authorized
    case unavailable(reason: String)
    case failed(reason: String)
}
```

XPC 接口只暴露固定方法：

```text
getCapabilities()
readPowerState()
setPowerMode(scope, mode)
readChargeLimit()
setChargeLimit(percent)
```

所有请求和响应使用明确的数据结构，不接受任意命令、脚本、路径或字符串参数。

## 5. Wi-Fi 数据流

### 5.1 Wi-Fi 开关

```text
用户切换开关
  ↓
ControlCoordinator
  ↓
CoreWLAN setPower
  ↓
NetworkProvider 事件/刷新
  ↓
读取真实开关状态
```

权限不足时返回 `authorizationRequired`，不把 UI 开关保持为成功状态。

### 5.2 网络连接

```text
扫描
  ↓
用户选择网络
  ↓
根据安全类型展示凭据表单
  ↓
后台执行 association
  ↓
等待 NetworkProvider 更新
  ↓
确认 SSID、BSSID 和 NWPath
  ↓
成功 / 失败 / 状态未确认
```

Personal、WEP、WPA/WPA2/WPA3 Personal、Enterprise 和其他系统能识别的安全类型都进入能力映射。系统无法表达的组合返回 `unsupportedSecurity`，并提供打开系统网络设置的入口。

### 5.3 记住网络

默认流程：

- `remember == false`：发起关联，不由 Duo Status 主动修改网络配置文件；不承诺覆盖 macOS 已有的全局记忆策略。
- `remember == true`：先完成连接，再更新/提交对应 `CWNetworkProfile`。
- 提交配置可能需要管理员授权。
- 提交失败不回滚连接，只返回“已连接，未能记住网络”。
- 不修改全局 `rememberJoinedNetworks` 设置。
- 本次操作不提供“忘记网络”，避免扩大权限和数据删除范围。

## 6. 电源数据流

### 6.1 应用启动

```text
读取 BatteryProvider
  ↓
读取公开 PowerPolicyProvider
  ↓
检查 SMAppService helper status
  ↓
如果已授权，查询 helper capabilities
  ↓
组合 PowerPolicyStatus
```

辅助进程未安装、未授权或不可用时，应用仍正常启动并保持只读。

### 6.2 启用高级控制

```text
用户点击“启用高级电源控制”
  ↓
注册 LaunchDaemon
  ↓
等待用户在系统设置中批准
  ↓
重新读取 SMAppService.status
  ↓
建立 NSXPCConnection
  ↓
查询能力
```

辅助进程空闲时不执行轮询，只在收到 XPC 请求时工作。用户可以在设置中停用并注销辅助进程。

### 6.3 写入和验证

```text
用户修改能源模式/充电上限
  ↓
校验能力和参数
  ↓
pending
  ↓
helper backend 写入
  ↓
helper 或主应用回读
  ↓
confirmed / writeUnconfirmed
  ↓
SystemStatusStore.refreshNow()
```

不做乐观更新。系统回读失败时保留旧状态并显示“状态未确认”。

## 7. 辅助进程安全边界

- 主应用和辅助进程分别签名。
- 辅助进程只接受来自主应用签名身份的 XPC 连接。
- XPC 请求使用 `NSXPCInterface` 和安全编码对象。
- 后备实现若调用系统命令，只能使用固定可执行文件路径和固定参数白名单。
- 禁止 `sh -c`、用户可控命令拼接和任意路径执行。
- 辅助进程不保存 Wi-Fi 密码、管理员密码或临时授权凭据。
- helper backend 读取不到可靠结果时报告 `unsupported` 或 `writeUnconfirmed`，不返回猜测值。

## 8. UI 改造

### 8.1 Wi-Fi 子面板

新增：

```text
UI/WiFiControlView.swift
UI/WiFiCredentialView.swift
```

功能：

- Wi-Fi 总开关。
- Personal Hotspots、Known Networks、Other Networks 分组。
- 扫描中、无网络、权限不足和扫描失败状态。
- 隐藏网络入口。
- Personal/Enterprise 凭据表单。
- “记住此网络”开关，默认关闭。
- Wi-Fi Settings 系统入口。
- 返回根状态弹窗。

### 8.2 电源控制

新增：

```text
UI/PowerControlView.swift
UI/PowerAuthorizationView.swift
```

Battery 区域显示：

- 当前能源模式。
- 电池侧和适配器侧能源模式。
- 80%–100% 充电上限控制。
- 辅助进程授权状态。
- 不支持或只读原因。

Settings 页面增加高级电源控制状态和注销入口，但不保存临时密码或系统电源状态副本。

## 9. 文件和 Xcode 工程改造范围

预计新增或修改：

```text
Domain/ControlModels.swift
Domain/WiFiModels.swift
Domain/PowerPolicyModels.swift
Providers/ProviderProtocols.swift
Providers/NetworkControlProvider.swift
Providers/PowerPolicyProvider.swift
State/SystemStatusStore.swift
State/PreferencesStore.swift
Control/CapabilityManager.swift
Control/ControlCoordinator.swift
Platform/CoreWLANNetworkController.swift
Platform/PowerHelperClient.swift
UI/WiFiControlView.swift
UI/WiFiCredentialView.swift
UI/PowerControlView.swift
UI/PowerAuthorizationView.swift
DuoStatusPowerHelper/...
```

Xcode 工程需要新增辅助进程 target、LaunchDaemon plist、XPC 配置、签名设置和应用包内资源拷贝阶段。主应用在辅助进程 target 不可用时仍必须可以构建只读版本。

## 10. 测试设计

### 10.1 纯逻辑测试

- `CWSecurity` 到 UI 安全类别的映射。
- 网络扫描结果按 `ssidData` 合并。
- 已知网络、可见网络和热点分组。
- 隐藏网络匹配。
- 充电上限边界 80% 和 100%。
- 非法充电上限被拒绝。
- 机型/系统版本导致的能力降级。
- 操作状态机和错误映射。

### 10.2 Provider 测试

- CoreWLAN 测试替身覆盖开放、Personal、WEP 和 Enterprise。
- 网络密码错误、网络消失、管理员授权失败。
- Wi-Fi 开关成功和失败。
- 电源模式能力组合。
- Charge Limit 仅在符合能力条件时可写。
- helper 未授权、断开和回读失败。

### 10.3 Coordinator 测试

- 同一领域禁止并发写入。
- 过期 `scanToken` 不能连接。
- 写入后等待状态确认。
- 超时不生成成功状态。
- 连接成功但记住网络失败的双结果。
- helper 失败后自动回退只读。

### 10.4 UI 测试

- Wi-Fi 开关状态与真实 Provider 保持一致。
- 三个网络分组正确展示。
- “记住此网络”默认关闭。
- Enterprise 表单可选择身份。
- 高级电源控制未授权时只显示启用入口。
- 充电上限初始显示当前值，不自动写入。
- 操作期间控件禁用并显示进行中状态。
- 中英文文案和 VoiceOver 标识完整。

### 10.5 实机验收

需要在 Apple silicon 设备上验证：

- 开放、WPA2/WPA3 Personal、隐藏和 Enterprise Wi-Fi。
- 已知网络和不可见网络。
- 个人热点被系统确认和无法确认的场景。
- Wi-Fi 开关权限行为。
- macOS 13–26 之间的能力降级。
- 支持 Charge Limit 的 macOS Tahoe 26.4+ 设备。
- 不支持 Charge Limit 的 Apple silicon 设备。
- Intel Mac 的只读行为。
- 辅助进程批准、拒绝、注销和升级。

## 11. 明确不包含的能力

- 远程设备控制。
- 云同步或账号系统。
- Duo Status 自己保存 Wi-Fi 密码。
- 任意 shell 命令执行。
- 自动猜测个人热点身份。
- 删除/忘记系统 Wi-Fi 网络。
- 一键“立即充满”操作；用户仍可通过 macOS 电池菜单执行。
- 在没有可靠后端时强行写入能源模式或充电上限。

## 12. 验收标准

合并版本完成的最低标准：

1. 现有 V1 只读状态功能不回归。
2. Wi-Fi 控制不阻塞主线程，支持确认范围内的安全类型和隐藏网络。
3. Wi-Fi 密码默认不保存，记住网络必须由用户逐次选择。
4. 已知网络和扫描网络按照系统状态正确分组。
5. 电源写入控件只在能力探测和授权都成功时显示。
6. Charge Limit 只在 macOS Tahoe 26.4+ Apple silicon 且后端可用时开放。
7. 所有写入操作都有回读确认和失败降级。
8. 辅助进程不可用时，主应用仍可作为稳定的只读菜单栏应用运行。
