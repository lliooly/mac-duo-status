# Duo Status 合并控制版本实现计划

## 目标

在不破坏 V1 只读状态链路的前提下，按
[合并控制能力设计](../specs/2026-09-15-merged-control-version-design.md)
实现 Wi‑Fi 控制、能源模式与充电上限能力探测、可选特权辅助进程，以及简洁的弹窗子面板。

## 实现顺序

### 阶段一：领域模型和测试替身

- 新增控制错误、能力状态、操作状态、Wi‑Fi 候选网络、凭据引用、电源策略模型。
- 扩展 `SystemStatusSnapshot`，加入 `PowerPolicyStatus`，保留旧状态字段和初始化行为。
- 扩展 Provider 协议，但为旧测试构造器保留默认的占位实现。
- 为安全类型映射、SSID 合并、已知网络分组、充电上限校验和操作状态机补充纯逻辑测试。

验收：只读状态相关测试全部通过，新模型没有任何密码或 XPC 对象字段。

### 阶段二：CoreWLAN 控制 Provider

- 使用 `CWWiFiClient` 提供的 `CWInterface`，在串行队列执行扫描、开关和关联。
- 将 `CWNetwork` 转换为值类型候选网络，并用 `scanToken` 拒绝过期扫描结果。
- 读取 `CWNetworkProfile`，按 `ssidData` 合并已知网络和扫描网络。
- 覆盖 CoreWLAN 可识别的安全类型；Enterprise 只接受密码或钥匙串身份引用。
- 连接成功后按用户的“记住此网络”选择提交配置；提交失败不回滚已建立的连接。
- 不修改全局 `rememberJoinedNetworks`，不保存任何凭据。

验收：Provider 可在没有真实网络的测试中被替身覆盖；CoreWLAN 错误会映射为稳定的 `ControlError`。

### 阶段三：ControlCoordinator 和状态刷新

- 新增 `ControlCoordinator`，在 `MainActor` 上串行化同一领域的写操作。
- 管理扫描生命周期、凭据表单临时状态和 `pending/succeeded/failed` 状态。
- 连接或开关完成后等待真实网络状态，再触发 `SystemStatusStore.refreshNow()`。
- 电源写入统一执行参数校验、写入、回读和未确认降级。

验收：过期 `scanToken`、同域并发写入、超时和“连接成功但记住失败”都有单元测试。

### 阶段四：能源模式、Charge Limit 和辅助进程边界

- 新增只读 `PowerPolicyProvider`，从 Foundation 与 IOKit 可公开读取的状态生成策略快照。
- 新增 `PowerHelperClient`，使用类型化 `NSXPCConnection`，并将辅助进程状态分为未安装、待批准、已授权、不可用和失败。
- 新增 `SMAppService` 按需注册/注销入口；启动时不安装、不请求权限。
- 新增独立 `DuoStatusPowerHelper` target、LaunchDaemon plist 和固定操作协议。
- 后端无法可靠探测或回读时返回 unsupported/writeUnconfirmed，不伪造状态，也不执行任意 shell。

验收：helper 不可用时主应用仍能构建、启动和显示 V1 状态；helper 请求只包含固定方法和结构化参数。

### 阶段五：极简 UI 和本地化

- 根弹窗保持现有摘要结构。
- Network 区增加“切换 Wi‑Fi 网络 >”，进入同一弹窗内的 Wi‑Fi 子面板。
- 子面板实现 Wi‑Fi 开关、Personal Hotspots（仅确认时显示）、Known Networks、Other Networks、隐藏网络和系统设置入口。
- 凭据表单支持 Personal、WEP、Enterprise 用户名/密码/钥匙串身份引用；“记住此网络”默认关闭。
- Battery 区显示当前能源模式、作用域、Charge Limit 和只读/授权状态；Settings 增加辅助进程状态与注销入口。
- 只增加必要的中英文文案、VoiceOver label 和 accessibility identifier。

验收：控件只在能力可用时开放；操作中禁用相关控件；不增加非必要说明性 UI。

### 阶段六：验证、审查和交付

- 执行格式检查、单元测试、UI 测试、Debug/Release 构建。
- 检查 App Sandbox、签名配置、helper 嵌入位置和 XPC 入口。
- 按中文代码审查清单复核架构、正确性、安全性、性能和可维护性，先修复所有必须修复项。
- 更新 `docs/architecture.md`、`docs/testing.md` 和 README 中的能力边界。
- 在当前工作区启动已构建应用，用 computer use 检查菜单栏弹窗、Wi‑Fi 子面板、设置入口和失败降级状态。
- 每完成一个可独立验证阶段提交一次中文 Conventional Commit；保持 `main` 分支，不创建 worktree。

## 关键不变量

- 主应用不以 root 运行。
- UI 不直接调用 CoreWLAN、IOKit、SMAppService 或 XPC。
- Wi‑Fi 密码、Enterprise 密码、私钥和临时授权凭据不进入 `UserDefaults`、日志或模型快照。
- 不对 Wi‑Fi 或电源写入做乐观更新；所有成功状态必须来自回读。
- 不执行 `sh -c`，不接受用户可控命令、路径或脚本。
- 辅助进程不可用时，V1 只读能力必须继续可用。
