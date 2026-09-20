# 状态采样与发布解耦实现计划

## 目标

将 `SystemStatusStore` 从“四个 Provider 共同完成后发布”改为按状态域独立采样、独立发布：电池/健康沿用高频采样，网络/电源策略采用事件驱动加 30 秒兜底；移除页面生命周期中的主动刷新，并让控制层只等待电源策略域。

## 实施步骤

### 1. 重构 `SystemStatusStore`

文件：`mac-duo-status/State/SystemStatusStore.swift`

- 为初始化器增加可注入的 `lowFrequencyRefreshIntervalNanoseconds`，默认值为 30 秒。
- 将单一采样任务拆为高频采样任务和网络/电源低频兜底任务。高频任务只请求电池、健康；低频任务只请求网络、电源策略，并在任务开始时完成各自首读。
- 为四个 Provider 分别维护 in-flight 任务和 pending 标记。相同域已有读取时合并请求，读取完成后最多补做一次排队读取，避免事件风暴产生并发平台查询。
- 使用生命周期代次保护异步结果：停止或睡眠时取消调度、使旧读取结果失效；唤醒后重新启动两个调度任务并请求四个域首读。
- 将 Provider 观察回调拆开：网络回调只请求网络；电源策略回调只请求电源策略；健康和电池回调只请求相关域。电池电源来源变化同时请求电源策略域，以便电源页的活动模式随 Battery/AC 作用域及时读回，但不触发网络或健康读取。
- 让每个域读取完成后单独更新对应缓存并重建 `snapshot`，不再等待其他 Provider。保留 `refreshNow()` 作为兼容入口，但它只提交四个独立请求；`refreshNowAndWait()` 等待这些独立任务完成。
- 增加电源域专用的 `refreshPowerPolicyNowAndWait()`，支持在已有电源读取进行时合并一次强制读回，并等待排队读回完成。
- 保持所有缓存和快照写入发生在 `@MainActor`，Provider 读取继续放在 utility detached task 中，避免慢的 CoreWLAN/helper 查询阻塞 Store 和 SwiftUI。

### 2. 改用电源域读回

文件：`mac-duo-status/Control/ControlCoordinator.swift`

- 将设置能源模式、请求 helper 授权、注销 helper 后的 `refreshNowAndWait()` 替换为 `refreshPowerPolicyNowAndWait()`。
- 保留现有读回匹配和操作状态流转，不改写入确认语义。

### 3. 移除页面主动刷新

文件：`mac-duo-status/UI/StatusPopoverView.swift`、`mac-duo-status/UI/PowerControlView.swift`

- 删除根弹出页 `.onAppear` 中的全量刷新。
- 删除电源页 `.onAppear` 和电源来源 `.onChange` 中的刷新调用。
- 保留页面对统一快照中电池和电源策略字段的读取；页面只消费 Store 状态，不参与调度。电源来源变化由 Store 的电池事件联动电源域刷新。

### 4. 增加并发和事件隔离测试

文件：`mac-duo-statusTests/mac_duo_statusTests.swift`

- 增加可控延迟/计数的 Battery、Network、Health、PowerPolicy 测试替身，验证慢网络或 helper 未完成时电池和健康仍可先发布。
- 验证网络事件只增加网络读取，电源策略事件只增加电源策略读取；电池电源来源事件允许增加电池和电源策略读取，但不增加网络/健康读取。
- 使用短注入间隔验证高频循环不会重复读取网络和电源，低频任务会按配置兜底读取。
- 验证同一域重叠请求会合并，停止后旧读取结果不会覆盖新生命周期状态。
- 验证 `refreshPowerPolicyNowAndWait()` 只读取电源策略，并保留现有统一快照和 Provider 失败隔离断言。
- 不覆盖或重写当前工作区已有的测试辅助改动；如同名替身已存在，扩展现有替身而不是重复定义。

### 5. 验证与收尾

- 使用 `git diff --check` 和静态搜索确认页面不再调用 `refreshNow`。
- 运行 macOS 单元测试 Scheme；必要时先用 `xcodebuild -list` 确认 Scheme 与 destination。
- 检查 `git diff`：实现改动应只涉及 Store、ControlCoordinator、两个页面、相关测试及本计划/规格文件；现有用户未提交的电源/helper、网络 Provider、Xcode 配置改动必须保持原样。

## 完成标准

- 慢网络或 helper 查询不会阻止电池/CPU 状态更新。
- 网络事件不再触发电池、健康、电源策略全量读取；电源事件不再触发无关 Provider。
- 网络/电源无事件时最多每 30 秒兜底读取一次。
- 打开弹出页或电源页不会额外启动全量刷新。
- 电源控制操作仍能在写入后完成准确读回确认。
- 新增测试和现有测试全部通过，且用户已有未提交改动没有被覆盖。
