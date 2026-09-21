# 菜单栏图标靠右设计

## 1. 目标

让 Duo Status 的菜单栏图标尽量位于右侧状态栏项目区域，并在系统允许时靠近用户指定的第二张图标左侧。点击图标仍打开现有状态面板，右键仍提供设置和退出入口。

## 2. 范围与限制

- 菜单栏入口从 SwiftUI `MenuBarExtra` 迁移到公开的 AppKit `NSStatusItem`。
- 现有 `SystemStatusStore`、`PreferencesStore`、`ControlCoordinator`、`StatusPopoverView` 和 `Settings` scene 保持不变。
- 使用稳定的 `NSStatusItem.autosaveName`，让系统保存状态栏项目的可见性和相关状态。
- 不使用私有 API、KVC 或未公开的排序优先级。
- macOS 没有公开“固定在另一个第三方图标左侧”的接口，因此只能尽量进入右侧状态栏项目区域；第三方图标之间的精确相邻关系仍由系统和用户的 Command-拖动排序决定。

## 3. 设计

`StatusItemController` 作为应用层的 AppKit 适配器，持有一个 `NSStatusItem` 和一个 `NSPopover`。状态栏按钮使用现有 `StatusIconRenderer` 生成图标，订阅统一状态快照和颜色偏好变化后更新图片。按钮左键展示由 `NSHostingController` 承载的现有 `StatusPopoverView`，并注入与原 `MenuBarExtra` 相同的环境对象。

右键或 Control-点击时，控制器弹出 AppKit `NSMenu`，菜单项复用现有本地化文案并调用现有设置入口或终止应用。`DuoStatusApp` 继续创建和持有所有状态对象，只移除 `MenuBarExtra` 场景入口并安装控制器；`Settings` scene 继续保留。

## 4. 数据流与生命周期

应用初始化状态对象后创建 `StatusItemController`。控制器在主线程创建状态栏项目、配置稳定 autosave 名称、创建弹出面板并订阅状态/偏好发布者。应用整个生命周期内复用同一个 status item 和 popover，不创建第二套状态刷新任务。

如果弹出面板正在展示，右键菜单出现前先关闭面板；设置窗口打开时沿用现有 `SettingsWindowAccess` 激活行为。状态栏图标更新失败不会影响状态采集或弹出面板。

## 5. 验收与验证

- 构建 macOS app target 和现有单元测试。
- 手动确认应用启动后只有菜单栏入口，图标显示在右侧状态栏项目区域。
- 左键打开现有状态面板，状态更新后图标同步变化。
- 右键或 Control-点击可打开本地化菜单，设置和退出动作仍可用。
- 重启应用后 status item 仍可见，位置由 macOS 状态栏规则和用户排序决定。

