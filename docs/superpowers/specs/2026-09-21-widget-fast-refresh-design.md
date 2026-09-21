# WidgetKit 尽快刷新设计

## 文档信息

- 状态：已确认，待规格审阅
- 更新时间：2026-09-21
- 目标平台：macOS 13 及更高版本
- 目标功能：让 Duo Status 方形小组件在状态变化后尽可能快地更新，同时接受 macOS WidgetKit 的系统调度延迟

## 1. 背景与约束

当前主应用的 `SystemStatusStore` 已经以约 1 秒的间隔采样电池和健康状态，并以约 30 秒的间隔刷新网络和电源策略。状态变化后，`WidgetStatusBridge` 会写入 App Group 共享快照，但小组件主动 reload 目前有 30 秒的应用侧节流，时间线兜底策略为约 60 秒后的 `after` 刷新。

WidgetKit 小组件不是持续运行的进程。`TimelineReloadPolicy.after` 只表示系统最早可以请求新时间线的时间；实际刷新仍可能受可见性、系统负载、每日预算和系统合并策略影响。Apple 建议只在小组件当前展示的内容发生变化时调用 `reloadTimelines`，并建议时间线更新间隔不要过短。因此本设计追求“尽快请求”，不承诺每秒或严格实时刷新。

## 2. 目标

- 主应用检测到小组件可见内容变化后，立即写入最新共享快照并请求 WidgetKit reload。
- 移除当前 `WidgetStatusBridge` 的 30 秒 reload 节流，使 WidgetKit 能在系统允许时尽早处理状态变化。
- 保留快照写入心跳，但心跳只用于维持更新时间，不因展示内容未变化而触发无意义 reload。
- 将时间线策略调整为约 5 分钟的兜底刷新，用于恢复时间线和更新过期显示；正常状态变化仍由事件驱动。
- 保持顶栏现有采样频率、Provider、App Group 数据格式、图标展示语义和过期弱化行为不变。
- 增加可验证的 reload 测试 seam，覆盖事件驱动刷新与心跳行为。

## 3. 非目标

- 不承诺小组件达到顶栏的 1 秒实时刷新效果。
- 不把 Widget Extension 改造成持续运行的后台进程，也不添加后台定时器、helper、XPC 或新的系统权限。
- 不修改主应用电池、网络、健康和电源策略 Provider 的采样频率或数据语义。
- 不改变小组件的布局、图标几何、颜色偏好、可访问性文案或 stale 状态视觉表现。
- 不修改当前工作区中与本设计无关的未提交文件。

## 4. 方案决策

### 4.1 选定方案：事件驱动 + 5 分钟兜底

状态更新链路保持如下结构：

```text
现有 Providers
      ↓
SystemStatusStore.rebuildSnapshot()
      ↓
WidgetStatusBridge
      ├─ 展示内容变化：写共享快照 + 立即请求 reload
      └─ 仅心跳到期：写共享快照，不请求 reload
      ↓
App Group 共享快照
      ↓
WidgetKit TimelineProvider
      └─ 当前 entry + 约 5 分钟后的兜底 policy
```

这个方案将应用侧延迟降到最低，同时把最终是否立即执行交给 WidgetKit。由于系统可能合并请求或耗尽预算，实际显示仍可能晚于共享快照写入。

### 4.2 未选方案

- 固定 5–10 秒 reload 节流：可以控制请求量，但会人为增加状态变化后的延迟，也不能绕过 WidgetKit 的系统预算。
- 继续使用固定 60 秒时间线刷新：实现最简单，但无法充分利用主应用已经知道的状态变化，仍会让用户等待下一次时间线。

## 5. 详细设计

### 5.1 WidgetStatusBridge

调整 `mac-duo-status/Widget/WidgetStatusBridge.swift`：

- 保留现有 `hasSameDisplayContent(as:)` 判断，展示内容变化仍以电池、网络、健康点和颜色偏好为准。
- 计算 `contentChanged` 和 `heartbeatDue`：
  - `contentChanged` 为真时必须写入快照并请求 reload。
  - 只有 `heartbeatDue` 为真时才写入快照，以更新 `updatedAt`；如果展示内容没有变化，不请求 reload。
  - 两者都为假时直接返回。
- 删除 `lastReloadDate` 状态和 `reloadMinimumInterval` 常量，避免应用侧 30 秒节流阻挡变化通知。
- 将 `WidgetCenter.shared.reloadTimelines(ofKind:)` 包装为可注入的 reload handler。生产环境默认调用 WidgetCenter，单元测试传入计数闭包，不改变生产 API 或 Widget kind。
- 为时间获取提供可注入的当前时间来源，默认使用 `Date()`，使心跳逻辑可以在测试中确定性验证。
- 只有共享快照写入成功后才请求 reload；写入失败时保留现有错误处理，不向 WidgetKit 发送无法读取到新数据的 reload 请求。

### 5.2 Widget 时间线

调整 `DuoStatusWidget/DuoStatusWidget.swift` 和共享常量：

- `getTimeline` 继续只读取 App Group 共享快照，不在 Widget Extension 中新增系统状态采集。
- 当前快照仍作为立即 entry 返回。
- `Timeline` 的 `policy` 改为当前时间约 5 分钟后的 `.after`，作为事件通知丢失、WidgetKit 重新激活或 stale 表现更新的兜底机制。
- 兜底时间只表示最早请求时间，不向用户承诺 5 分钟准时更新；WidgetKit 仍可以延后或合并请求。
- `getSnapshot`、占位状态、不可用状态、过期透明度和现有图标渲染保持不变。

### 5.3 共享快照与主应用

- 继续使用现有 App Group 文件快照和单一 JSON key，不改变字段和编码格式。
- `SystemStatusStore` 继续在展示字段变化时调用 `WidgetStatusBridge.publish`。
- 主应用原有的 1 秒电池/健康采样和 30 秒网络/电源刷新不做调整；这次只改变 Widget 快照发布后的 reload 触发策略。
- 当主应用被系统暂停或退出时，小组件保留最后一次成功写入的真实快照；下次主应用产生变化时重新触发事件驱动 reload。

## 6. 错误处理与资源边界

- App Group 快照写入失败：不调用 WidgetKit reload，小组件继续使用现有快照或不可用状态。
- WidgetKit reload 被系统延后、合并或忽略：不添加高频重试；后续状态变化和 5 分钟兜底时间线仍提供恢复机会。
- 展示内容未变化但心跳到期：只更新时间戳，避免无意义的 WidgetKit 请求。
- Widget 无法读取快照：沿用现有 `.unavailable()` 路径，不执行新的系统查询。
- 不通过每秒 `reloadTimelines` 强行模拟实时 UI，避免无效的系统负载和刷新预算消耗。

## 7. 测试与验收

### 7.1 自动化测试

- 首次发布快照时，验证共享快照写入成功且 reload handler 调用一次。
- 展示内容发生变化时，验证连续两次变化都能立即调用 reload，不受原 30 秒节流影响。
- 展示内容未变化且心跳尚未到期时，验证不重复写入且不调用 reload。
- 展示内容未变化但心跳到期时，验证更新时间被写入，但 reload handler 不被调用。
- 写入失败时，验证 reload handler 不被调用。
- 保留现有 Widget 快照编码、读取、不可用状态和共享容器测试。

### 7.2 构建与手工验收

- 构建 `mac-duo-status` 和 `DuoStatusWidget` targets，并运行主应用单元测试。
- 主应用运行期间改变电池、网络或健康展示状态，确认共享快照先更新，WidgetKit 在系统允许时尽快显示新状态。
- 在状态连续变化时确认不会因为应用侧 30 秒节流而固定等待下一次 reload。
- 在状态没有变化时确认心跳不会导致小组件反复重载。
- 确认 WidgetKit 延迟刷新时，小组件仍显示最后一次真实状态；快照过期后沿用现有弱化逻辑。
- 记录实际观察到的 WidgetKit 调度延迟，但不将其作为代码层面的固定时间保证。

## 8. 规格自检

- 没有未解决的 TODO、占位符或待定实现选项。
- 目标、数据流、错误处理和验收标准均围绕“事件驱动、尽快请求、系统最终调度”保持一致。
- 5 分钟仅作为 WidgetKit 兜底 policy，不与“尽可能快的事件驱动刷新”矛盾。
- 没有改变主应用状态源、App Group 数据协议或当前工作区无关改动的范围。
- 测试 seam 足以验证应用侧不再存在 30 秒 reload 节流，以及心跳不会触发无意义 reload。
