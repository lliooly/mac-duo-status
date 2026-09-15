# Duo Status 架构说明

## 1. 文档目的

本文档描述 Duo Status 的代码边界和数据流，覆盖 V1 基础状态能力以及合并后的 Wi-Fi/电源控制层。

当前版本采用混合实现：原有状态链路继续负责只读快照，独立控制层负责用户主动发起的写入。控制能力按平台支持度和授权状态降级，不能写入时仍保持完整的只读体验。

## 2. 当前工程状态

当前工程已经完成基础状态与合并控制版本的主要骨架：

- 主场景使用 MenuBarExtra。
- 设置场景使用 Settings。
- 领域层包含状态模型、健康分数计算和平滑采样基础。
- State 层包含 SystemStatusStore、事件/定时刷新和 PreferencesStore。
- Providers 层包含协议、真实 Apple 平台适配器和测试替身。
- Control 层包含 Wi-Fi 控制协调器、电源策略控制协议和独立操作状态。
- CoreWLAN 已接入扫描、已知网络合并、连接和 Wi-Fi 开关；凭据只在当前操作期间存在。
- 电源策略已接入公开低电量模式读取、能力模型和辅助进程 XPC 合同。实际电源写入后端不可用时，界面明确降级为只读。
- `DuoStatusPowerHelper` 已作为可签名、可授权的 LaunchDaemon 目标接入工程，但主应用不会因为辅助进程不可用而阻塞启动。
- UI 层包含组合图标、弹出面板、状态区域和设置面板。
- 单元测试覆盖纯逻辑、测试替身和统一状态源。

Xcode 默认的 WindowGroup、NavigationSplitView、SwiftData 和 Item 示例已经移除。

设置面板中的开机启动开关通过 macOS 13 的 SMAppService 注册或取消主应用登录项。

## 3. 目标分层

目标结构分为四层，并在状态层旁边增加独立控制链路：

1. 应用层：管理 MenuBarExtra、设置窗口和应用生命周期。
2. 状态层：统一管理状态快照、刷新任务和配置同步。
3. Provider 层：分别读取电池、网络和系统健康状态。
4. 平台适配层：封装 Apple API、辅助进程客户端和系统设置入口。

建议的依赖方向：

    UI → SystemStatusStore → Provider protocols → Apple platform adapters
    UI → ControlCoordinator → Control protocols → CoreWLAN / XPC helper
    UI → PreferencesStore

UI 不直接调用 IOPowerSources、NWPathMonitor、CoreWLAN、Mach API 或 XPC。

## 4. 核心组件

### 4.1 SystemStatusStore

SystemStatusStore 是菜单栏图标、弹出面板和设置面板共享的唯一状态源。

职责：

- 保存最新的状态快照。
- 启动和停止 Provider 刷新。
- 接收事件驱动更新。
- 按周期更新 CPU 和系统负载。
- 将状态更新提交到主线程或 MainActor。
- 标记暂不可用和过期数据。
- 将用户选择的健康指标映射为组合图标需要的摘要。

SystemStatusStore 不负责绘制图标，也不负责直接存储用户偏好。

### 4.2 BatteryProvider

职责：

- 判断是否存在内置电池。
- 读取当前容量和最大容量。
- 计算 0% 至 100% 的电量。
- 读取适配器供电状态和供电来源。
- 读取低电量模式状态。
- 提供电池变化通知。

使用 IOPowerSources 读取电池基础信息。电源策略单独由 `PowerPolicyProvider` 读取，避免把策略写入混入基础电池 Provider。

### 4.3 NetworkProvider

职责：

- 读取连接状态。
- 读取当前接口类型。
- 读取网络名称。
- 读取 Wi-Fi RSSI 并映射为信号级别。
- 区分 Wi-Fi、有线网络、个人热点和未连接。
- 在无法确认个人热点时回退到普通 Wi-Fi。
- 提供当前 SSID、BSSID、接口名和 Wi-Fi 开关状态，供控制层在操作完成后重新读取。

连接类型和连接状态使用 NWPathMonitor 补充。Wi-Fi 名称和 RSSI 使用 CoreWLAN。`NetworkProvider` 只负责读状态；`CoreWLANNetworkController` 独立负责扫描、连接和 Wi-Fi 开关。

### 4.4 HealthProvider

职责：

- 读取 CPU 使用率。
- 读取 1 分钟、5 分钟和 15 分钟系统负载。
- 读取系统热状态。
- 对 CPU 和负载提供平滑后的采样值。
- 计算当前指标的健康分数。
- 映射为 0 至 4 个健康点。

CPU 统计可以使用公共 Mach 接口，系统负载使用 getloadavg，热状态使用 ProcessInfo。

健康分数公式和热状态分值以 product-spec.md 为准。平滑算法、边界限制和采样参数仍待确认。

### 4.5 控制能力与降级

控制模型和 `ControlCoordinator` 判断功能是否：

- 不支持。
- 只能读取。
- 可以修改。
- 需要用户授权。
- 被用户拒绝。
- 辅助进程不可用或写入后读回未确认。

UI 根据能力状态决定是否显示区域、只读值或操作控件，不直接根据 macOS 版本硬编码 UI。Wi-Fi 和电源操作分别维护 pending/succeeded/failed 状态，不能使用乐观更新。

Wi-Fi 使用 CoreWLAN 完成本机控制；电源控制使用可选的 `SMAppService` LaunchDaemon 和 XPC 合同。主应用不以 root 运行，也不把管理员密码交给主应用。

### 4.6 PreferencesStore

PreferencesStore 负责保存：

- 健康指标选择。
- 开机启动选项。
- 图标外观。
- 弹出面板各区域的默认折叠状态。

不保存管理员密码、Wi-Fi 密码或临时授权凭证。

骨架阶段使用 UserDefaults 作为轻量默认实现。PreferencesStore 通过初始化参数接收 UserDefaults，后续可以替换为其他实现而不改变 UI 和产品契约。

## 5. 状态模型

状态模型建议保持为不可变快照，避免三个界面分别拼装数据。

快照至少包含：

- 更新时间。
- 电池状态。
- 网络状态。
- 电源策略状态和辅助进程能力。
- 系统健康状态。
- 各 Provider 的可用性和错误状态。

电池状态至少包含：

- 是否有内置电池。
- 当前电量。
- 是否正在充电。
- 供电来源。
- 低电量模式。

网络状态至少包含：

- 连接状态。
- 接口类型。
- 网络名称。
- Wi-Fi RSSI。
- 信号级别。
- 是否确认个人热点。

控制结果不直接写入快照；操作成功后必须触发状态源重新读取，由真实读回结果更新快照。

健康状态至少包含：

- CPU 使用率。
- 1 分钟、5 分钟和 15 分钟负载。
- 热状态。
- CPU、温度、负载三种健康分数。
- 当前选中的健康指标。
- 0 至 4 个健康点。

当前骨架已经将 UI 与 Provider 之间的交互限制在模型和协议上，不能依赖原始平台字典。

## 6. 刷新和并发

事件型状态：

- 电池变化由 IOPowerSources 通知触发。
- 网络变化由 NWPathMonitor 触发。
- 热状态变化由 ProcessInfo 通知触发。
- 低电量模式变化由系统通知触发。

采样型状态：

- CPU 和负载按照固定周期采样。
- 骨架默认使用约 2 s 的采样间隔；平滑窗口仍待确认。
- 菜单栏图标关闭时仍保持采样。
- 系统睡眠时允许暂停。
- 唤醒后重新读取完整快照。

并发约束：

- Provider 采集不阻塞 UI。
- 状态快照提交到 MainActor。
- 同一时间只保留一套刷新任务。
- 面板打开不创建第二个轮询器。
- 旧快照必须带有过期或暂不可用标记，不能伪装成最新数据。

## 7. UI 数据流

    Provider events / timer
              ↓
    SystemStatusStore
       ↙       ↓       ↘
  MenuBarExtra  Popover  Settings

    Popover control action → ControlCoordinator → backend
                                           ↓
                                  readback → SystemStatusStore

菜单栏图标只读取状态摘要。弹出面板读取完整快照和操作能力。设置面板读取 PreferencesStore 和能力模型，并通过统一状态源观察即时同步结果。

健康指标在弹出面板中切换时：

1. 更新 PreferencesStore。
2. 让 SystemStatusStore 重新计算健康摘要。
3. 菜单栏图标和弹出面板同时刷新。
4. 设置面板显示新的选中值。

## 8. UI 和应用场景

目标应用场景：

- 应用启动后以菜单栏应用方式运行。
- 不强制打开复杂主窗口。
- 点击菜单栏图标打开原生弹出面板。
- 通过弹出面板底部或上下文菜单打开设置，并通过上下文菜单退出。
- 设置面板是独立的长期配置入口。

骨架使用 MenuBarExtra 的 window style 和 Settings Scene。窗口尺寸、视觉细节以及最终交互仍可在 UI 开发阶段调整，不改变上述职责边界。

## 9. 平台 API 边界

当前使用的官方读取和控制适配：

- IOPowerSources。
- Network.framework 的 NWPathMonitor 和 NWPath。
- CoreWLAN。
- Foundation 的 ProcessInfo。
- 公共 Mach CPU 统计接口。
- getloadavg。
- CoreWLAN 的网络扫描、连接和 Wi-Fi 开关。
- `SMAppService`、LaunchDaemon 和 XPC，用于可选的电源辅助进程。

工程不使用私有 API、管理员密码采集、任意 shell 拼接或让主应用整体以 root 运行。电源写入后端当前可以返回“不支持/不可用”，此时主应用继续展示公开 API 的只读结果。

由于 macOS 对沙盒主应用与非沙盒 LaunchDaemon 的组合有部署限制，当前主应用 target 不启用 App Sandbox；这不改变主应用不以 root 运行的边界。发布构建仍需使用签名和 notarization 流程验证辅助进程授权。

## 10. 错误和能力降级

Provider 不应把所有错误都转成应用级 fatal error。推荐将错误转换成：

- 当前值不可用。
- 当前值过期。
- 能力不支持。
- 需要授权。
- 操作失败。

UI 根据状态显示中性图形、简短说明或隐藏对应控件。一个 Provider 失败不能阻断其他 Provider。

## 11. 安全边界

- 主应用不以 root 身份运行，也不请求管理员密码。
- Wi-Fi 凭据只存在于当前连接调用和安全输入控件生命周期内，不写入 UserDefaults、日志或模型持久层。
- “记住此网络”由用户明确选择，默认关闭；关闭时应用不主动提交配置文件，但不宣称覆盖 macOS 的全局记忆策略。
- 电源辅助进程仅暴露固定 XPC 方法，并校验调用方签名身份；主应用不执行任意 shell 命令。
- 所有写入采用 pending → backend → readback → confirmed/writeUnconfirmed 流程。超时、授权失败和后备实现失败都必须如实展示。

## 12. 骨架阶段不应提前决定的内容

以下内容不在当前架构说明中替用户决定：

- CPU 和负载平滑算法。
- 系统负载健康分数超出 0 至 1 时的边界处理。
- 开机启动使用的具体 API。
- Intel Mac 启动后的行为。
- 设置窗口的具体视觉布局。

这些内容在实现前逐项确认，确认结果再回写本文档。
