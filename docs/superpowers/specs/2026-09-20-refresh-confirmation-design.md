# 刷新与电源写入确认修复设计

## 目标

修复 `SystemStatusStore.refreshNowAndWait()` 在已有定时刷新进行时提前返回的问题，避免电源模式已经写入成功却因状态快照仍是旧值而被报告为“写入未确认”。

## 范围

- 修改 `SystemStatusStore` 的刷新并发协调：并发刷新请求共享正在进行的刷新并等待其完成。
- `refreshNowAndWait()` 在调用时已有刷新进行中时，等待该刷新完成后再确保执行一次新的刷新，使写操作后的状态读取发生在写入之后。
- 保持 `ControlCoordinator` 的确认顺序：写入、底层直接回读、状态仓库刷新、快照确认。
- 增加覆盖旧刷新与写入交错场景的回归测试。

## 非目标

- 不改变电源模式能力探测、写入协议、错误类型或 UI 状态机。
- 不修改现有未提交的 Xcode scheme 用户设置文件。
- 不引入 worktree 或无关重构。

## 架构与数据流

`SystemStatusStore` 继续在 `MainActor` 上维护唯一快照。刷新入口拆分为两种语义：普通刷新在已有刷新时合并并等待；写入确认使用的 `refreshNowAndWait()` 若加入了已有刷新，则在其完成后再发起或加入一个后续刷新。这样，写操作之前启动的刷新不会成为写入后的最终快照来源。

电源操作流程保持：

```text
setPowerMode
    -> readPowerMode（写入后的底层回读）
    -> refreshNowAndWait（写入后的状态刷新）
    -> 检查 SystemStatusSnapshot.powerPolicy
```

## 错误处理

刷新仍然不抛出业务错误；Provider 的不可用状态继续由各 Provider 返回并写入快照。只有底层回读失败或刷新后的快照不匹配时，`ControlCoordinator` 才报告现有的 `writeUnconfirmed`。停止采样只取消采样循环，不取消正在等待的刷新调用。

## 测试策略

- 保留现有并发写入保护和底层回读失败测试。
- 增加一个可控的电源状态 Provider：第一次读取阻塞并返回旧模式，写入完成后放行；后续读取返回新模式。
- 通过 `ControlCoordinator.setPowerMode` 验证：协调器会等待旧刷新结束、执行写入后的刷新，并最终进入 `succeeded`，且 Provider 至少完成两次读取。
- 运行 macOS 单元测试并检查工作区差异，确认只包含本次修复和规格文档。
