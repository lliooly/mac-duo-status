# 移除 Wi‑Fi 联网控制设计

## 1. 背景与目标

当前应用的 Wi‑Fi 二级页面包含扫描、系统已知网络展示、隐藏网络发现、凭据输入、网络连接、记住网络和 Wi‑Fi 开关等能力。调查确认应用无法提供可靠的原生联网体验，因此本次调整移除应用内 Wi‑Fi 联网控制，只保留网络状态读取。

本次目标：

- 根页面网络卡继续显示当前连接网络和 Wi‑Fi 信号强度。
- 根页面原本进入自定义 Wi‑Fi 二级页面的按钮，改为直接打开 macOS 系统 Wi‑Fi 设置。
- 删除自定义 Wi‑Fi 二级页面及其前端、控制层、CoreWLAN 写入逻辑、授权逻辑和 helper/XPC 联网后端。
- 保留电源控制、网络状态读取、网络类型识别和信号等级映射。

本次不包含：

- 不改变电池、电源模式、健康状态和菜单栏图标逻辑。
- 不新增应用内 Wi‑Fi 配置、密码存储或系统网络代理。
- 不改变根页面已有的有线网络、未连接和热点状态判定规则。

## 2. 用户体验

### 2.1 根页面网络卡

根页面网络卡继续使用 `SystemStatusStore.snapshot.network`：

- 当前 Wi‑Fi 连接时显示 SSID 和信号等级。
- 有线网络、热点、断开或不可用状态继续使用现有状态文案和图标。
- 只有普通 Wi‑Fi 连接显示 Wi‑Fi 信号图标；热点和非 Wi‑Fi 网络不显示 Wi‑Fi 信号强度。

当前网络卡右下角的“切换网络”动作不再导航到应用内页面，而是调用现有 `SettingsWindowAccess.openWiFiSettings()`，直接打开系统 Wi‑Fi 设置页面。按钮更新为系统设置语义对应的本地化文案和无障碍标识。

### 2.2 自定义 Wi‑Fi 页面

删除 `WiFiControlView` 和 `WiFiCredentialView`，同时删除 `StatusPopoverView` 中的 `.wifi` 导航目标和相关过渡。应用不再提供自定义 Wi‑Fi 二级页面。

### 2.3 设置页面

删除应用设置中的 Wi‑Fi 生物识别/联网授权区块。应用不再主动扫描、连接或修改 Wi‑Fi，因此不再需要应用级 Wi‑Fi 授权标记、Touch ID/密码验证或定位授权。

## 3. 架构与数据流

调整后的网络数据流为：

```text
NWPathMonitor + CoreWLAN 只读状态
        ↓
NetworkProvider
        ↓
SystemStatusStore.snapshot.network
        ↓
StatusPopoverView 网络卡
        ├─ 显示当前网络与信号
        └─ SettingsWindowAccess.openWiFiSettings()
```

`NetworkProvider` 继续负责读取连接类型、SSID、RSSI 和信号等级，并通过现有观察机制触发状态刷新。控制层不再参与网络状态读取，也不再持有网络控制对象。

`SettingsWindowAccess.openWiFiSettings()` 保持现有的系统设置 URL 回退顺序和应用激活行为；系统设置跳转失败时不在应用内新增错误状态，网络状态仍以只读 provider 的下一次刷新结果为准。

## 4. 代码边界调整

### 4.1 删除的应用前端与控制代码

- 删除 `mac-duo-status/UI/WiFiControlView.swift`。
- 删除 `mac-duo-status/UI/WiFiCredentialView.swift`。
- 从 `StatusPopoverView` 删除 Wi‑Fi 二级导航，只保留根页面和电源页面。
- 从 `SettingsView` 删除 Wi‑Fi 授权状态、授权按钮、撤销按钮及相关环境对象。
- 将 `ControlCoordinator` 收敛为电源操作协调器：删除网络操作状态、扫描、开关、连接、连接确认和网络授权依赖。

### 4.2 删除的网络控制后端

- 删除 `CoreWLANNetworkController.swift` 及其中的扫描、开关、连接、凭据和网络记忆逻辑。
- 删除 `WiFiAuthorization.swift`。
- 删除 `WiFiLocationAuthorization.swift`。
- 从 `ProviderContainer` 移除 `networkControl` 依赖和 placeholder/live 实例。
- 从 `PowerHelperClient` 移除 `SavedWiFiNetworkConnecting`、Wi‑Fi 请求超时、保存网络连接方法及 Wi‑Fi 专用错误映射。

### 4.3 删除的模型与协议

- 从 `WiFiModels.swift` 删除 Wi‑Fi 安全类型、网络候选、凭据、连接结果、扫描合并/分组和网络控制协议；如果文件不再包含只读模型，则删除整个文件。
- 从 `ControlModels.swift` 删除只服务于联网控制的错误类型和凭据引用；保留电源控制仍使用的错误、操作状态和 helper 状态模型。
- 从应用端和 helper 端 `PowerHelperProtocol` 删除 `connectToSavedWiFi`。
- 删除 `DuoStatusPowerHelper/WiFiHelperBackend.swift`。
- 从 `DuoStatusPowerHelper/PowerHelperService` 删除 Wi‑Fi backend 注入、XPC 方法和 Wi‑Fi 错误编码；helper 只保留电源 backend。

helper 协议版本从 4 提升到 5，并同步修改客户端和服务端常量，确保已安装的旧 helper 不会被误当作当前协议使用。重新注册 helper 时使用新的电源专用实现。

### 4.4 保留的只读能力

- `NetworkProvider`、`NetworkProviding` 和 `NetworkStatus` 保留。
- `NetworkSignalMapper` 保留。
- `SettingsWindowAccess.openWiFiSettings()` 保留并作为根页面按钮动作。
- 与电源模式相关的 `PowerHelperClient`、`PowerHelperProtocol`、`PowerHelperService` 和 `PowerPolicyProvider` 保留。

当前工作区中为 Wi‑Fi 开关新增的 `NetworkSetupWiFiPowerCommandRunner` 及其测试属于本次删除的联网控制链路，随控制器一并移除；网络 provider 中仅为只读展示所需的逻辑保留。

## 5. 本地化与文档

清理只被删除的扫描、连接、凭据、授权、网络安全和控制错误本地化键；保留网络标题、当前状态、信号和打开系统 Wi‑Fi 设置所需文案。

同步更新以下文档中的产品边界和架构描述：

- `README.md`
- `docs/architecture.md`
- `docs/product-spec.md`
- `docs/testing.md`

文档应明确：应用只读展示当前网络状态，用户通过系统 Wi‑Fi 设置完成网络连接和切换。

## 6. 测试与验收

### 6.1 自动化验证

- 更新单元测试，移除扫描、连接、记住网络、凭据、授权、网络控制协调器和 Wi‑Fi helper 测试替身。
- 保留并验证 RSSI 到四级信号映射、Wi‑Fi/热点/有线状态显示规则和 `NetworkProvider` 的只读状态行为。
- 更新电源控制测试以匹配只包含电源依赖的 `ControlCoordinator` 初始化接口。
- 使用 `rg` 检查以下符号不再出现在应用和 helper 源码中：
  `NetworkControlProviding`、`CoreWLANNetworkController`、`WiFiCredentialView`、`connectToSavedWiFi`、`WiFiAuthorizationProviding`、`WiFiSavedNetworkBackend`。
- 执行应用构建、单元测试和 `build-for-testing`，确认主应用与 helper 均能编译。

### 6.2 手工验收

- 打开菜单栏面板，确认网络卡仍显示当前连接网络；Wi‑Fi 已连接时显示信号强度。
- 点击网络卡动作按钮，确认直接打开系统 Wi‑Fi 设置，不出现应用内 Wi‑Fi 二级页。
- 确认应用启动和刷新过程中不弹出 Wi‑Fi 扫描、定位、联网授权或凭据输入界面。
- 分别验证有线、未连接、SSID 不可读和 RSSI 不可读时，应用保留真实连接状态且不显示错误的 Wi‑Fi 信号。
- 确认电源控制和设置页面其他区块不受影响。

## 7. 风险与回退

- 删除 XPC 方法会使旧 helper 与新客户端协议不一致；协议版本提升和 helper 重新注册用于避免混用，旧 helper 不会被继续视为可用版本。
- macOS 系统设置 URL 可能随系统版本变化；继续使用现有多级回退。若所有 Wi‑Fi 专属 URL 均失败，保留现有回退行为，不影响应用内只读状态展示。
- CoreWLAN 读取 SSID/RSSI 仍受 macOS 系统权限和设备状态影响；权限不足时只显示可确认的连接状态，并将名称或信号显示为不可用，不自行推断。
- 本次删除集中在 Wi‑Fi 控制边界，不回退或重写电源、健康和网络状态读取的无关实现。
