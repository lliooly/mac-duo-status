# Duo Status 方形中心徽章小组件设计

## 文档信息

- 状态：已确认
- 更新时间：2026-09-20
- 目标平台：macOS 13 及更高版本
- 目标功能：增加一个可添加到 macOS 桌面或通知中心的方形 WidgetKit 小组件
- 实现边界：前端优先，不新增状态 Provider、采样器、Domain 规则或控制后端

## 1. 目标

为 Duo Status 增加一个只展示当前三合一状态的方形小组件。小组件采用中心徽章型构图：以 Liquid Glass 方形容器承载现有三合一状态图标，使电池、网络和系统健康仍然能通过一个紧凑图形快速识别。

小组件必须复用主应用已经生成的 `SystemStatusSnapshot`，不复制电池、网络或健康状态的采集逻辑。主应用仍是状态的唯一来源；Widget 只负责读取共享快照、生成时间线和绘制界面。

## 2. 范围

### 2.1 包含

- 新增一个 WidgetKit Extension target。
- 仅支持方形 `systemSmall` family。
- 添加中心徽章型 Liquid Glass 视觉容器。
- 复用现有三合一图标的电池环、网络符号和健康点语义。
- 将现有状态快照转换为 Widget 专用的轻量可编码展示快照。
- 使用 App Group 在主应用和 Widget 之间共享展示快照。
- 复用现有彩色图标偏好。
- 支持 macOS 26+ 的官方 Liquid Glass 和 macOS 13–25 的原生材质降级。
- 增加快照映射、存取和不可用状态测试。

### 2.2 不包含

- 新的电池、网络、健康或电源策略 Provider。
- Widget 自己采集系统状态。
- 新的后台服务、helper、XPC 或远程服务。
- 修改 `SystemStatusStore` 的数据语义、刷新频率或并发策略。
- Widget 内的按钮、控制操作、设置入口或复杂详情页。
- 文字型状态卡、历史图表或多尺寸 Widget。

## 3. 视觉设计

### 3.1 容器

- Widget 内容为正方形，使用连续圆角矩形作为外轮廓。
- macOS 26 及以上使用 SwiftUI 官方 `.glassEffect(.clear, in:)`，让系统负责 Liquid Glass 的折射、材质和环境适配。
- macOS 13–25 使用 `.ultraThinMaterial` 作为降级背景，并保留轻量描边与阴影。
- 不绘制自定义黑色底板、渐变玻璃或大面积噪声纹理，避免与系统 Widget 容器叠加。
- 玻璃容器不承担任何状态语义；状态只由中心徽章表达。

### 3.2 中心徽章

徽章复用当前 `CombinedStatusIcon` 的三部分语义：

- 电池：环形进度表示电量，沿用充电、低电量和低电量模式的颜色规则。
- 网络：中心使用 Wi-Fi、以太网、个人热点、断开或不可用对应的 SF Symbol。
- 健康：四个点表示当前选中健康指标的评分；没有数据时全部使用弱化颜色。

Widget 需要比菜单栏图标更大的绘制尺寸，同时保持内部留白，使徽章不会贴近玻璃边缘。Widget 的中性前景色随浅色/深色外观自适应；电池是否使用彩色仍由现有 `PreferencesStore.usesColor` 决定。

不额外显示电量百分比、SSID、CPU 数值或更新时间，保持中心徽章型的识别优先级。

### 3.3 状态表达

- 电池没有内置电池时：保留弱化的空电池环，不显示伪造电量。
- 电池数据不可用时：电池环不显示有效进度，维持弱化状态。
- 网络断开或不可用时：使用现有 `NetworkKind` 对应的断开/不可用图标。
- 健康数据不可用时：四个健康点全部弱化。
- 共享快照超过 10 分钟未更新时：整体徽章降低透明度，保留最后一次真实状态，不生成新的数值。

## 4. 数据流与共享快照

### 4.1 单一状态来源

数据流保持如下边界：

```text
现有 Providers
      ↓
SystemStatusStore
      ↓
WidgetStatusBridge（前端适配层）
      ↓
App Group 共享快照
      ↓
WidgetKit TimelineProvider
      ↓
中心徽章视图
```

`WidgetStatusBridge` 只负责监听现有快照和 `usesColor` 偏好，将展示所需字段写入共享存储。它不是新的状态源，也不执行系统查询。

### 4.2 WidgetStatusSnapshot

新增 Widget 专用 DTO，放在 app 与 Widget target 都能访问的共享目录中。DTO 至少包含：

- 写入时间。
- 电池是否可用、是否有内置电池、电量比例、充电状态和低电量模式。
- 网络类型和网络可用性所需的展示字段。
- 健康点数量及其可用性。
- `usesColor` 偏好。

DTO 使用 `Codable`，不直接让现有 `SystemStatusSnapshot` 或带关联值的领域状态承担跨进程编码职责。

### 4.3 App Group

主应用和 Widget 使用同一个 App Group：

```text
group.com.shishishi3.mac-duo-status
```

共享快照使用 App Group `UserDefaults` 中的单个 Data 值保存。写入内容保持原子替换；读取不到快照时，Widget 使用占位数据或不可用状态，不执行额外系统查询。

主应用只在展示字段发生变化，或达到低频心跳间隔时更新快照。WidgetKit reload 请求进行合并和节流，不让当前约 1 秒的健康采样频率直接变成 Widget 刷新频率。

## 5. WidgetKit 结构

新增 `DuoStatusWidget` Extension target，Bundle ID 使用：

```text
com.shishishi3.mac-duo-status.widget
```

Widget 使用 `StaticConfiguration`：

- 支持 `systemSmall`。
- `placeholder` 使用稳定的示例状态，保证 Widget 添加流程中有完整视觉预览。
- `getSnapshot` 从 App Group 读取当前快照；无快照时返回可识别的不可用状态。
- `getTimeline` 返回当前快照，并以约 60 秒后的下一次读取作为时间线策略。
- Widget 不注册后台定时器，不创建 Provider，不调用主应用控制逻辑。

现有图标绘制器抽取为 app 与 Widget 可共同编译的展示层代码。主应用的菜单栏图标和 Widget 使用相同的几何与状态语义，但可以分别传入菜单栏或 Widget 所需的前景色。

## 6. 文件与职责

实现时预计新增或调整以下前端文件，具体路径可按 Xcode target 组织微调：

- `mac-duo-status/Widget/WidgetStatusSnapshot.swift`：Widget 展示 DTO 和领域状态映射。
- `mac-duo-status/Widget/WidgetStatusSnapshotStore.swift`：App Group 快照读写。
- `mac-duo-status/Widget/WidgetStatusBridge.swift`：从现有 Store 投递快照并节流 WidgetKit 刷新。
- `mac-duo-status/Widget/DuoStatusWidget.swift`：WidgetKit 配置、Provider 和入口视图。
- `mac-duo-status/Widget/WidgetStatusBadge.swift`：Liquid Glass 容器和中心徽章布局。
- 现有 `CombinedStatusIcon`/绘制器相关文件：抽取可共享的图标展示部分，不改变菜单栏调用方式。
- 主应用和 Widget 的 entitlement：加入同一个 App Group。
- `mac-duo-status.xcodeproj/project.pbxproj`：加入 Widget Extension target、资源和嵌入关系。

除 Widget 快照适配和共享展示代码外，不修改 Provider、Helper、Control、Domain 规则或采样计划。

## 7. 可访问性与兼容性

- Widget 提供明确的无障碍标签，说明 Duo Status 以及电池、网络、健康三部分状态。
- 颜色不是唯一的状态表达方式；断开、不可用和健康点数量仍通过图形结构表达。
- 使用 `#available(macOS 26.0, *)` 包裹 Liquid Glass 分支，保证 macOS 13–25 编译和运行。
- Widget 的状态快照与主应用本地化设置不引入新的可见文案，因此不增加新的本地化页面内容。
- App Group 不保存账号、密码、网络凭据或远程数据，只保存当前 Mac 的展示状态。

## 8. 测试与验收

### 8.1 自动化测试

- 验证 `SystemStatusSnapshot` 到 `WidgetStatusSnapshot` 的字段映射。
- 验证 DTO 编码、解码和 App Group 存取。
- 验证无快照、不可用电池、断开网络、不可用健康数据和过期快照的展示状态。
- 验证彩色图标偏好进入 Widget 快照。
- 验证共享图标绘制器在 app 与 Widget target 中均可编译。
- 构建主应用和 Widget Extension，并运行现有单元测试。

### 8.2 手工验收

- 将 Widget 添加到 macOS 桌面或通知中心，确认方形玻璃容器和中心徽章比例。
- 在浅色、深色和不同桌面背景下确认对比度与 Liquid Glass 层次。
- 修改电池、网络和健康状态后确认 Widget 最终读取到最新共享快照。
- 关闭主应用后确认 Widget 保留最后一次真实状态，并在过期后弱化显示。
- 检查 macOS 26+ 官方玻璃分支和旧系统材质降级分支。
- 确认不新增后台进程、系统权限、Provider 查询或控制后端。

## 9. 规格自检结论

- 没有未解决的 TODO、占位需求或待定选项。
- 中心徽章型、只支持 `systemSmall`、前端优先和无新后端约束在各章节一致。
- Widget 的跨进程数据需求通过轻量 App Group 适配层解决，没有复制现有状态采集链路。
- WidgetKit 刷新受系统预算限制，因此设计明确使用共享快照、时间线和节流，而不承诺每秒实时刷新。
- 现有未提交的业务代码改动不属于本规格范围，实施时必须保留。
