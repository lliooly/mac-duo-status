# 小组件共享快照读取修复设计

## 文档信息

- 状态：已确认方案，待实现前审阅
- 更新时间：2026-09-20
- 目标平台：macOS 13 及更高版本

## 1. 目标

修复 Duo Status 小组件无法读取主应用状态快照、因此一直显示不可用徽章的问题。修复只覆盖小组件侧的共享快照读取层，不改变主应用的状态采集、Provider、采样器、状态发布或其他 UI 逻辑。

## 2. 已确认的现象与原因范围

- App Group `group.com.shishishi3.mac-duo-status` 中已经存在 `widget.status.snapshot` 数据，数据结构完整。
- 小组件当前通过 `WidgetStatusSnapshotStore` 读取该数据；读不到或解码失败时统一返回 `nil`，Provider 随后显示 `.unavailable()`。
- 生产环境的 `WidgetStatusSnapshotStore` 会长期持有一个 `UserDefaults(suiteName:)` 实例，并在 App Group 不可用时静默回退到 `.standard`。后者是小组件进程自己的默认域，不是主应用的共享域，会掩盖真实读取失败并导致小组件持续显示不可用状态。
- `CFPrefsPlistSource` 日志和布局递归日志不作为新的业务数据源或状态错误处理分支；本修复不通过修改主应用逻辑或重做小组件布局来处理它们。

## 3. 方案

### 3.1 共享快照存取层

调整 `mac-duo-status/Widget/WidgetStatusSnapshotStore.swift`：

- 生产环境不缓存 `UserDefaults` 实例；每次读取或写入时重新创建指定 App Group 的 `UserDefaults`。
- 生产环境不再回退到 `UserDefaults.standard`。如果 App Group 实例无法创建，读操作返回 `nil`，写操作返回 `false`。
- 继续支持测试传入自定义 `UserDefaults`，使现有编码、解码和存取测试保持隔离且不依赖真实 App Group。
- 快照仍使用现有单一 key `widget.status.snapshot` 和 JSON `Codable` 格式，不改变字段、编码格式或主应用写入协议。

### 3.2 Provider 行为

不修改 `DuoStatusWidgetProvider` 的状态语义和时间线策略：

- `getSnapshot` 和 `getTimeline` 继续从 `WidgetStatusSnapshotStore` 读取快照。
- 没有快照或快照无法解码时继续显示 `.unavailable()`，避免伪造状态。
- 读取成功后沿用现有的过期透明度处理和图标渲染逻辑。

数据流保持为：

```text
主应用现有状态发布
        ↓
App Group UserDefaults
        ↓
小组件每次读取时新建的共享快照存储
        ↓
WidgetKit TimelineProvider
        ↓
现有状态徽章
```

## 4. 错误处理与范围约束

- 不引入新的 Provider、系统查询、后台任务、控制操作或权限。
- 不读取 App Group 容器中的底层 plist 文件，避免依赖系统内部存储路径。
- 不改变主应用的 `WidgetStatusBridge` 写入和 WidgetKit reload 节流逻辑。
- 不把 `.standard` 作为生产环境的共享数据兜底；失败时明确保持不可用状态。
- 不为 `CFPrefsPlistSource` 或 SwiftUI 布局日志新增业务重试、布局改造或日志屏蔽逻辑。

## 5. 测试与验收

自动化验证包括：

- 现有快照 JSON 编码/解码和自定义 `UserDefaults` 存取测试继续通过。
- 增加测试覆盖：在同一共享 suite 写入新快照后，新的读取实例能读取最新快照，证明读取不依赖初始化时的旧缓存。
- 增加测试覆盖：生产读取路径不会将缺失的 App Group 数据回退到独立标准域；缺失数据返回 `nil`。
- 构建 `DuoStatusWidget` target，确认 WidgetKit 和共享展示文件均可编译。
- 运行现有主应用单元测试，确认主应用状态采集和发布逻辑未被修改。

手工验收包括：

- 主应用已经产生快照时，重新加载或重新添加小组件可以显示真实电池、网络和健康状态。
- 主应用关闭后，小组件仍能读取最后一次共享快照。
- 没有共享快照或快照损坏时，小组件仍显示明确的不可用状态，而不是显示错误的标准域数据。

## 6. 非目标

- 不修复或重构主应用的 App Group 配置、状态发布链路、采样频率和 WidgetKit 刷新预算。
- 不调整小组件的 Liquid Glass 背景、徽章几何、布局或视觉样式。
- 不处理与状态读取无关的系统日志噪声。

## 7. 规格自检

- 没有未解决的待办、占位符或待定实现选项。
- 读取、写入、失败处理和测试范围与“只改小组件逻辑”的约束一致。
- 没有引入直接读取系统偏好 plist 的高风险替代方案。
- 主应用已有未提交改动不属于本规格范围，实施时必须保留。
