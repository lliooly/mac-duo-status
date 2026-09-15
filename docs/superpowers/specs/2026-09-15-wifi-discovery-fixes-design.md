# Wi-Fi 扫描与二级页面问题修复设计

日期：2026-09-15

## 1. 背景

Wi-Fi 控制页已经具备扫描、已知网络合并、连接凭据输入、隐藏网络入口和多接入点选择基础，但当前有四个用户可见问题：

1. 已知网络即使本次扫描没有出现，仍会显示在“已知网络”分组中。
2. 普通扫描无法可靠展示“其他网络”。
3. 隐藏网络入口点击后没有形成可用的输入和定向扫描流程。
4. “Wi-Fi 设置”打开的是网络总页，没有进入 Wi-Fi 专属页面。

本次修复聚焦 Wi-Fi 控制页和它依赖的扫描数据链路，不改变密码存储策略、连接确认策略或电源控制能力。

## 2. 目标与非目标

### 2.1 目标

- 已知网络只展示当前扫描发现的网络。
- 其他网络只展示当前普通扫描发现的网络。
- 隐藏网络入口可展开，输入 SSID 后执行真正的定向扫描。
- 隐藏网络不存在时明确显示“找不到网络”错误。
- 不因 RSSI 缺失而禁用已经发现的网络。
- Wi-Fi 设置优先打开 macOS 的 Wi-Fi 专属页面。
- 在需要时请求 macOS 定位授权，使 CoreWLAN 能返回扫描网络的 SSID 信息。
- 为扫描合并、隐藏扫描和设置跳转增加可验证的测试覆盖。

### 2.2 非目标

- 不实现忘记网络、自动保存密码或后台自动连接。
- 不重做整个 Wi-Fi 控制页的视觉样式。
- 不新增网络历史记录、信号图表或后台持续扫描。
- 不把 Wi-Fi 扫描迁移到第三方 API。
- 不改变同 SSID 多 BSSID 的选择交互。

## 3. 当前问题与根因

### 3.1 已知网络的来源没有区分

`CoreWLANNetworkController` 会将 `CWNetworkProfile` 和本次 `scanForNetworks` 结果合并。仅来自配置文件的候选网络没有 RSSI，但 `WiFiControlView` 仍将它们放入“已知网络”分组，因此未被发现的网络也会显示为置灰条目。

仅依赖 `rssi == nil` 不能表达“是否被扫描发现”：扫描结果可能因为系统权限或设备状态缺少 RSSI，但仍然是有效的扫描结果。

### 3.2 扫描网络的 SSID 可能不可读

CoreWLAN 的 `CWNetwork.ssid` 和 `ssidData` 在调用应用没有定位授权时可能为空。当前合并逻辑在 `ssidData` 为空时直接丢弃网络，因此“其他网络”会变成空列表。可读的 `ssid` 但缺少 `ssidData` 时还可以使用 UTF-8 数据作为连接缓存的回退键；两者都不可读时不能安全地构造网络候选。

### 3.3 定向扫描会混入所有已知网络

隐藏网络扫描传入 SSID 后，底层仍然把全部系统网络配置文件合并进候选列表。即使定向扫描没有返回目标网络，只要系统存在任意已知配置，结果就不为空，导致 `networkNotFound` 判断失效。

### 3.4 隐藏输入区域的位置不稳定

隐藏网络输入区域当前位于固定高度 `ScrollView` 的懒加载内容末尾。展开后可能被滚动区域遮住，用户无法直接看到入口已经生效。扫描错误也只依赖通用操作状态，缺少稳定的展开区域承载。

### 3.5 设置链接指向网络总页

当前链接使用 `x-apple.systempreferences:com.apple.preference.network`，它只保证打开网络设置容器，不保证选中 Wi-Fi 页面。

## 4. 设计

### 4.1 候选网络模型

在 `WiFiNetworkCandidate` 增加 `isDiscovered: Bool` 字段，默认值为 `false`，用于表示候选是否来自当前一次扫描：

| 来源 | `isKnown` | `isDiscovered` |
| --- | --- | --- |
| `CWNetworkProfile` | `true` | `false` |
| 普通扫描返回的 `CWNetwork` | `false` 或由合并结果决定 | `true` |
| 已知网络与扫描结果合并 | `true` | `true` |
| 隐藏网络定向扫描结果 | 由是否匹配配置文件决定 | `true` |

同 SSID 合并时，`isDiscovered` 使用逻辑或；扫描结果的 SSID、安全能力、BSSID 和接入点列表继续使用现有的合并策略。`rssi` 只负责信号展示，不再承担“是否发现”的语义。

`WiFiNetworkCandidateMerger` 与平台控制器内部的合并逻辑保持相同规则，避免测试模型与真实扫描模型产生不同结论。

### 4.2 扫描数据流

扫描链路保持在 `CoreWLANNetworkController`，分为普通扫描和定向扫描两种模式：

```text
请求扫描
  ↓
定位授权检查（首次扫描时请求）
  ↓
CoreWLAN scanForNetworks
  ├─ 普通扫描：扫描结果 + 配置文件 → 合并候选
  └─ 定向扫描：只保留请求 SSID 的扫描结果 → 合并匹配配置文件
  ↓
更新扫描 token、缓存和候选列表
```

#### 普通扫描

- 使用 `scanForNetworks(withSSID: nil, includeHidden: false)`。
- 对每个扫描网络优先使用 `network.ssidData`。
- `ssidData` 缺失但 `network.ssid` 可读时，使用 `Data(ssid.utf8)` 作为回退值。
- 两者都不可读时跳过该网络，因为无法构造稳定的候选键或连接目标。
- 扫描结果候选标记为 `isDiscovered = true`，再与系统配置文件合并。
- 成功扫描后更新 `lastScanToken`、`lastInterfaceName` 和 BSSID 缓存。

#### 定向扫描

- 使用用户去除首尾空白后的 SSID UTF-8 数据。
- 使用 `scanForNetworks(withSSID: requestedSSID, includeHidden: true)`。
- 只接受解析后的 SSID 数据与 `requestedSSID` 完全相等的网络。
- 合并时只保留请求 SSID 对应的系统配置文件，不返回其他已知网络。
- 没有匹配结果时抛出 `ControlError.networkNotFound`。
- 只有成功找到目标后才更新扫描 token、候选列表和缓存；失败时保留错误状态。

普通扫描与定向扫描共享安全类型映射、BSSID 合并和连接解析逻辑，不改变已有的连接凭据流程。

### 4.3 定位授权

新增平台层定位授权桥接对象，例如 `WiFiLocationAuthorization`，由 `CoreWLANNetworkController` 在扫描前调用：

- 已授权时直接继续扫描。
- 状态为 `notDetermined` 时请求 macOS “使用期间”授权，并等待授权回调。
- 用户拒绝或系统限制时返回授权失败，映射为现有的 `ControlError.authorizationRequired`。
- 不在应用启动时请求，不进行定位采集，也不保存位置数据。

应用的生成 Info.plist 增加 `NSLocationWhenInUseUsageDescription`，并为英文和简体中文提供对应描述。定位授权只用于让 CoreWLAN 暴露扫描网络的 SSID 信息，不改变应用的网络连接范围。

### 4.4 Wi-Fi 控制页

`WiFiControlView` 的分组规则改为：

- 热点：`hotspotConfirmation == .confirmed && isDiscovered`。
- 已知网络：`isKnown && isDiscovered && hotspotConfirmation != .confirmed`。
- 其他网络：`!isKnown && isDiscovered && hotspotConfirmation != .confirmed`。

当已知网络为空时，不渲染“已知网络”分组；当其他网络为空时保留“其他网络”分组和空状态提示，便于用户确认普通扫描已经完成。RSSI 缺失不再让已经发现的网络行变灰或禁用。

隐藏网络入口改为显式的展开/收起状态：

- 按钮使用动态的展开/收起图标，并提供稳定的 `wifi-hidden-network-toggle` 标识。
- 输入区域移动到扫描 `ScrollView` 外，位于网络列表和底部操作行之间。
- SSID 为空或只有空白时禁用扫描按钮。
- 扫描时复用现有 pending 状态，防止并发扫描。
- 扫描失败时在 Wi-Fi 控制页显示对应错误；找不到目标时显示 `networkNotFound` 的本地化文案。
- 扫描成功后使用候选列表中的目标网络继续现有的凭据输入和连接流程。

普通刷新仍执行普通扫描；用户需要重新点击刷新才能从定向扫描结果回到完整的普通扫描列表。

### 4.5 系统设置跳转

在 `SettingsWindowAccess` 中增加 `openWiFiSettings()`，统一激活应用并按顺序尝试 Wi-Fi 专属 URL：

1. `x-apple.systempreferences:com.apple.wifi-settings`
2. `x-apple.systempreferences:com.apple.wifi-settings-extension`
3. `x-apple.systempreferences:com.apple.preference.network?Wi-Fi`
4. 最后回退到当前的网络总页 URL，兼容无法识别专属 URL 的系统版本。

`WiFiControlView` 不再直接拼接 URL，只调用该入口。专属 URL 可用时，“Wi-Fi 设置”会直接进入 Wi-Fi 页面。

## 5. 错误处理

| 场景 | 处理 |
| --- | --- |
| 定位权限待决定 | 请求授权，等待结果后再扫描 |
| 定位权限被拒绝或受限 | 显示 `authorizationRequired`，不伪造网络列表 |
| 普通扫描返回空集合 | 成功完成扫描，展示其他网络空状态 |
| 隐藏 SSID 为空 | UI 禁用扫描按钮，不调用控制层 |
| 隐藏 SSID 找不到 | 返回 `networkNotFound`，保留输入区域并显示错误 |
| 扫描结果没有 SSID 信息 | 跳过无法构造的条目；其他可读网络继续展示 |
| Wi-Fi 关闭 | 不执行扫描；系统配置文件不会因为“未发现”而展示 |
| 设置专属 URL 不受支持 | 依次回退到兼容 URL，最后打开网络总页 |

连接、密码错误、记住网络失败和操作确认继续沿用现有状态机，不在本次设计中改变。

## 6. 测试计划

### 6.1 纯逻辑测试

在 `mac-duo-statusTests` 增加或调整测试：

- 只有系统配置文件的已知网络为 `isDiscovered == false`。
- 已知网络与扫描结果合并后为 `isKnown == true` 且 `isDiscovered == true`。
- 未配置过的扫描网络保留在合并结果中，并标记为已发现。
- 扫描结果无 RSSI 但有 SSID 仍能作为已发现候选。
- 定向结果过滤后不会包含其他 SSID 或无关已知配置。
- SSID 回退数据只在 `ssidData` 缺失且 `ssid` 可读时生成。

### 6.2 UI 行为测试

在 UI 测试可稳定启动菜单栏窗口的环境中覆盖：

- 已知网络未发现时不出现该网络行。
- 点击隐藏网络入口后，SSID 输入框立即出现在可见区域。
- 输入 SSID 后扫描按钮可用；空输入时不可用。
- 定向扫描失败时错误文案仍保留在隐藏网络区域附近。
- Wi-Fi 设置入口优先进入专属 Wi-Fi 页面。

当前仓库的 UI runner 可能在连接菜单栏应用前被系统终止，因此这些用例同时保留手动验收步骤，不把 runner 启动失败误判为功能断言失败。

### 6.3 构建与手动验收

- 执行 macOS 单元测试。
- 执行应用构建和 `build-for-testing`。
- 在目标 Mac 上确认首次扫描会出现定位授权提示。
- 授权后确认普通扫描可以展示未保存的其他网络。
- 确认未扫描到的已知网络不显示。
- 确认隐藏网络可输入、定向扫描、找不到时显示错误、找到后可进入连接。
- 确认 Wi-Fi 设置按钮直接进入 Wi-Fi 页面。

## 7. 兼容性与风险

- CoreWLAN 的 SSID/BSSID 信息仍受系统定位授权和系统隐私设置控制；拒绝授权时无法安全展示未知网络，这是系统限制，界面必须明确显示授权失败。
- System Settings URL 属于系统入口标识，可能随 macOS 版本变化；多级回退保证入口仍可用，但只有专属 URL 成功时才能保证直接落到 Wi-Fi 页面。
- `isDiscovered` 是本次扫描生命周期字段，不写入 UserDefaults，也不影响系统已知网络配置。
- 本次不修改 XPC、电源辅助进程、密码持久化或网络连接确认逻辑。
