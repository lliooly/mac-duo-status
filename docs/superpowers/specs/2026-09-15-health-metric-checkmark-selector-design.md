# 健康指标对号选择器设计

## 文档信息

- 日期：2026-09-15
- 范围：弹出面板与设置面板中的健康指标选择
- 状态：已获用户批准，待实现

## 目标

将当前横向分段选择器统一替换为纵向三行选择器。每行对应一个健康指标，当前选项在右侧显示对号，整行可点击。弹出面板和设置面板复用同一个 SwiftUI 组件，保持交互、选中状态和视觉语言一致。

## 方案与取舍

采用可复用的自定义 SwiftUI 选择器，而不是继续使用 `Picker` 的系统样式或 `Menu`：

- 自定义组件能保证两个页面都稳定呈现三行，不受容器和 macOS Picker 样式差异影响。
- `Menu` 仍然需要用户展开，且三项不会持续可见，不符合本次交互目标。
- `.inline` Picker 的系统间距和背景可控性有限，难以在弹出面板和设置页中保持一致。

## 组件设计

新增一个仅负责展示和提交选择的 `HealthMetricSelector`：

- 输入：`Binding<HealthMetric>`。
- 内容：遍历 `HealthMetric.allCases`，显示现有本地化标题。
- 每个选项使用 `Button`，整行响应点击。
- 当前选项使用 `checkmark` 图标；未选项保留同等宽度的尾部空间，避免切换时布局跳动。
- 使用轻量的选中背景、圆角和悬停反馈，适配深色/浅色外观。
- 为每行提供明确的无障碍标签、选中状态和按钮行为。

组件不负责保存偏好、不直接刷新状态，也不引入新的模型或本地化键。

## 页面接入

### 弹出面板

`StatusPopoverView.healthDetails` 删除当前 `.segmented` Picker，改为在“指标”标题下放置 `HealthMetricSelector`。选择绑定继续通过现有 `statusStore.setHealthMetric(_:)` 写入，以保持选择后菜单栏健康摘要和弹出面板立即刷新。

### 设置面板

`SettingsView` 的“指示器”区域删除当前 Picker，改用同一个 `HealthMetricSelector`，直接绑定 `preferences.healthMetric`。保留现有 `onChange` 调用 `statusStore.setHealthMetric(_:)` 的同步逻辑，确保设置页和弹出面板使用同一个持久化选择。

## 数据流与边界

```text
HealthMetricSelector
        ↓ Binding<HealthMetric>
PreferencesStore ←→ SystemStatusStore
        ↓                 ↓
 SettingsView       StatusPopoverView
```

组件只提交合法的 `HealthMetric` 枚举值。现有状态不可用时的详情展示逻辑不变；选择器本身仍然显示三项，因为指标选择是配置入口，不依赖当前采样值是否可用。

## 错误处理

本次改动不增加新的外部调用或失败路径。状态刷新、指标计算和不可用状态继续由 `SystemStatusStore` 与现有详情逻辑处理。若某项指标暂不可用，仍按现有逻辑显示“暂不可用”，不禁用或隐藏选择项。

## 验证计划

1. 构建 `mac-duo-status` scheme，确认 SwiftUI 泛型、Binding 和 macOS 13 部署目标均可编译。
2. 运行现有单元测试和 UI 测试。
3. 手动确认弹出面板和设置页都显示三行；点击任意行后对号只出现在当前项。
4. 在两个页面交替切换指标，确认选择即时同步、重新打开后仍保留，并确认深色外观下文字和选中背景具备足够对比度。

## 非目标

- 不修改 `HealthMetric`、`PreferencesStore` 或状态计算逻辑。
- 不增加新的健康指标、下拉菜单行为或动画依赖。
- 不改变电池、网络和其他折叠区域。
