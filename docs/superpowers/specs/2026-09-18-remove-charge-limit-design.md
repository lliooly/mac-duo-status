# 移除充电上限能力设计

## 目标

从 Duo Status 中完整移除尚无可靠公开后端的“充电上限”能力，避免 UI、领域模型、
XPC 协议和 helper 长期保留不可用的占位代码。

本次只移除充电上限。电池状态读取、Battery 区域、按供电来源保存的能源模式、
helper 安装与授权、Wi-Fi helper 能力以及打开系统 Battery 设置的入口均保持不变。

## 删除范围

### UI 与控制流

- 删除 `PowerControlView` 中的充电上限状态、控件和应用操作。
- 删除弹出面板中充电上限的只读状态行。
- 删除 `ControlCoordinator.setChargeLimit`，不改变能源模式操作状态机。
- 删除中英文充电上限标题、当前值和非法范围错误文案。

### 领域模型与 Provider

- 删除 `ChargeLimitValidator`。
- 从 `PowerCapabilities` 删除允许值集合及其派生能力状态。
- 从 `PowerPolicyStatus` 删除当前上限及其能力状态。
- 从 `PowerControlProviding` 删除读取和写入充电上限的方法。
- 删除 `ControlError.invalidChargeLimit`。
- `PowerPolicyProvider` 不再请求或转发充电上限，但继续组合公开 Low Power 状态、
  helper 能源模式读回与 helper 状态。

### XPC 与 helper

- 主应用和 helper 两份 `DuoStatusPowerHelperProtocol` 同步删除充电上限读写方法。
- `getCapabilities` 只返回能源模式作用域和支持模式。
- `readPowerState` 只返回 Battery、AC 和当前生效能源模式。
- `PowerBackendCapabilities`、`PowerBackend.readPowerState` 与具体后端删除充电上限
  占位字段和方法。
- helper 协议发生不兼容变化，因此主应用期望修订号与 helper 修订号同时递增一次，
  继续使用现有旧 helper 修复流程。

## 明确保留的边界

- 不改 `BatteryProvider`、`BatteryStatus`、电量百分比或充电状态判断。
- 不改 `PMSetPowerModeParser`、`PMSetProcessRunner` 或能源模式写入参数。
- 不改 helper 注册、授权、重装或版本握手机制，只更新协议修订号。
- 不改 Wi-Fi 扫描、连接或保存网络能力。
- 不加入快捷指令、SMC、私有框架或新的替代充电控制方案。
- 不创建 worktree，不整理与本次删除无关的现有工作区修改。

## 文档策略

更新 README、当前产品规格、架构说明和测试说明，使它们不再把充电上限描述为
现有或计划能力。既有设计规格和实现计划作为历史记录保留，并在合并控制版本设计
顶部标注充电上限部分已被本设计取消，不重写其余历史内容。

## 测试与验收

- 删除充电上限校验、能力映射、协调器拒绝写入和测试替身中的对应用例与字段。
- 调整所有 `PowerCapabilities`、`PowerPolicyStatus`、helper 协议和测试替身构造调用。
- 保留并运行能源模式解析、能力探测、写入后读回、helper 版本与授权测试。
- 全仓搜索确认生产代码、本地化资源和当前文档中不存在活动的充电上限接口。
- 构建主应用与 helper，并运行测试套件；失败时只修复由本次删除造成的问题。

## 完成标准

应用中不再显示、读取或尝试设置充电上限，代码中也不再存在为该能力预留的活动
协议和状态字段。同时，能源模式、电池状态、helper 授权、Wi-Fi 控制和系统设置回退
保持原有行为。
