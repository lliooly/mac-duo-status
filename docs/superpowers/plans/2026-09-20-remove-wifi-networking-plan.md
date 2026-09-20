# 移除 Wi‑Fi 联网控制实现计划

## 目标

按照
[移除 Wi‑Fi 联网控制设计](../specs/2026-09-20-remove-wifi-networking-design.md)
，让应用只读显示当前网络和 Wi‑Fi 信号，并把根页面网络操作直接指向 macOS 系统 Wi‑Fi 设置。删除应用内扫描、连接、凭据、记住网络、Wi‑Fi 开关、联网授权及 helper/XPC 联网能力，同时保留电源控制和网络状态读取。

## 实现顺序

### 阶段一：收敛根页面入口和应用依赖

- 在 `StatusPopoverView` 删除 `.wifi` 目标、Wi‑Fi 页面分支和导航过渡。
- 将网络卡当前的“切换网络”按钮改为调用 `SettingsWindowAccess.openWiFiSettings()`，更新本地化文案与 accessibility identifier。
- 删除 `WiFiControlView.swift`、`WiFiCredentialView.swift`。
- 从 `DuoStatusApp` 和 `SettingsView` 移除 `LocalAuthenticationWiFiAuthorizer` 的环境对象、初始化和注入。
- 从 `SettingsView` 删除 Wi‑Fi 授权设置区块，但保留电源授权和其他设置。

验收：应用源码不再引用 Wi‑Fi 二级页面或 Wi‑Fi 授权对象；网络卡保留当前网络名和信号显示；电源页面仍能获得 `ControlCoordinator`。

### 阶段二：移除网络控制协调层和领域模型

- 将 `ControlCoordinator` 收敛为只依赖 `PowerControlProviding` 的电源操作协调器。
- 删除网络操作状态、候选网络数组、连接结果、扫描/开关/连接方法、网络读回等待和网络匹配逻辑。
- 从 `ProviderContainer` 删除 `networkControl` 字段、初始化参数、placeholder 和 live 实例。
- 删除 `NetworkControlProviding`、`SavedWiFiNetworkConnecting` 及 Wi‑Fi 候选、凭据、连接结果、扫描合并/分组和安全类型模型。
- 删除只服务于联网控制的 `ControlError` 分支和 `KeychainIdentityReference`；保留电源写入和 helper 状态仍使用的错误。

验收：控制层的初始化只需要状态仓库和电源控制；网络状态读取仍由 `SystemStatusStore` 通过 `NetworkProviding` 独立刷新；单元测试中的网络控制替身全部移除。

### 阶段三：移除 CoreWLAN 写入与应用级授权

- 删除 `CoreWLANNetworkController.swift`，包括扫描、Wi‑Fi 电源开关、连接、凭据读取和网络配置提交。
- 删除 `WiFiAuthorization.swift` 和 `WiFiLocationAuthorization.swift`。
- 保留 `NetworkProvider.swift` 的只读 `NWPathMonitor`/CoreWLAN 状态读取、RSSI 映射和观察机制。
- 清理 `NetworkProvider` 中仅为已删除 Wi‑Fi 开关服务的状态字段或读取逻辑；不要删除根页面仍使用的只读网络信息。
- 处理现有未提交修改：与 `CoreWLANNetworkController` 绑定的 Wi‑Fi 电源命令 runner 和对应测试随控制器删除；`NetworkProvider` 中仍服务只读展示的变更按设计保留。

验收：应用只会读取网络状态，不会创建扫描、关联、密码或定位授权流程；RSSI/信号等级纯逻辑测试保留。

### 阶段四：删除 helper/XPC 联网协议

- 从应用端和 helper 端 `PowerHelperProtocol` 删除 `connectToSavedWiFi`。
- 从 `PowerHelperClient` 删除保存网络连接协议 conformance、Wi‑Fi 超时、XPC 调用和 Wi‑Fi 错误转换。
- 删除 `DuoStatusPowerHelper/WiFiHelperBackend.swift`。
- 从 `PowerHelperService` 删除 Wi‑Fi backend 注入、方法实现和 Wi‑Fi 错误编码；只保留电源 backend。
- 将应用端 `expectedHelperRevision` 与 helper 端 `helperRevision` 从 4 同步提升到 5。

验收：helper 编译只依赖电源 backend；应用端 XPC 接口不再暴露网络连接方法；旧 helper revision 不会被当作当前版本使用。

### 阶段五：清理测试、本地化和文档

- 删除扫描、连接、凭据、记住网络、联网授权、Wi‑Fi helper 和网络控制 coordinator 测试及私有替身。
- 调整电源 coordinator 测试的构造参数，保留电源写入回读、并发保护和失败状态测试。
- 保留网络信号等级、Wi‑Fi/热点/有线显示规则和网络 provider 只读测试；保留与本次无关的工作区测试修改仅在仍可编译时使用。
- 删除仅服务于 Wi‑Fi 控制/授权/安全类型/错误的中英文本地化键，保留网络标题、状态、信号和系统 Wi‑Fi 设置文案。
- 更新 `README.md`、`docs/architecture.md`、`docs/product-spec.md`、`docs/testing.md`，明确网络连接由系统设置完成。

验收：`rg` 不再找到已删除的网络控制协议、页面、授权和 helper 符号；文档不再把应用描述为可扫描或连接 Wi‑Fi。

### 阶段六：验证与交付

- 执行 `git diff --check`。
- 执行主应用 Debug 构建、单元测试和 `build-for-testing`，覆盖主应用与 helper target。
- 如本机条件允许，启动构建产物手工确认网络卡按钮直接打开系统 Wi‑Fi 设置，且不出现自定义二级页、定位授权或凭据输入。
- 检查工作区 diff，确保不回退用户已有的无关修改；不创建 worktree，保持当前 `main` 分支。

## 关键不变量

- `NetworkProvider` 是唯一的网络状态读取入口；UI 不直接访问 CoreWLAN。
- 应用不再执行 Wi‑Fi 扫描、关联、断开、开关切换或密码/钥匙串凭据读取。
- helper 只提供电源模式能力，Wi‑Fi 连接方法不再存在于协议或实现中。
- 当前网络、连接类型和 Wi‑Fi 信号展示不因删除控制层而退化。
- 电源控制、健康状态、电池状态和菜单栏摘要不改变行为。
