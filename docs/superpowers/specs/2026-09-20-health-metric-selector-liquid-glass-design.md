# HealthMetricSelector 胶囊 Liquid Glass 样式设计

## 目标

将共用的 `HealthMetricSelector` 从普通分段控件调整为参考图中的胶囊形 Liquid Glass 风格，并在状态弹窗与设置页保持一致。

## 范围

- 仅调整 `mac-duo-status/UI/HealthMetricSelector.swift` 的 SwiftUI 展示样式。
- 保留现有 `Binding<HealthMetric>`、三项指标、本地化文案、选择动画、hover 反馈和辅助功能标识。
- 不修改状态模型、偏好设置、数据采集、持久化或页面布局。

## 视觉方案

- macOS 26 及以上仅在整个选择器外层使用 SwiftUI 官方 `.glassEffect(.clear, in: Capsule(...))`，让控件呈现为一个整体玻璃胶囊，而不是多个玻璃按钮。
- 选中项使用普通的半透明高亮胶囊，继续通过 `matchedGeometryEffect` 在指标之间平滑移动；选中项不再叠加第二层 Liquid Glass。
- macOS 13–25 使用 `.ultraThinMaterial` 和简洁描边/阴影作为降级路径；不手写渐变来伪装系统玻璃。
- 未选中项保持低对比度文字；hover 只增加轻微前景色填充，不改变布局。

## 交互与可访问性

- 选择逻辑和 `health-metric-*` accessibility identifier 保持不变。
- 当前选项继续添加 `.isSelected` trait。
- 遵循 `accessibilityReduceMotion`：减少动态效果时取消胶囊移动动画。

## 验证

- 编译 macOS 应用目标，确认 `#available(macOS 26.0, *)` 分支和 macOS 13 材质降级均可用。
- 运行现有单元测试；确认状态选择逻辑未受影响。
- 检查状态弹窗和设置页均使用新的胶囊选择器。
