# 电源适配器供电状态修正设计

## 背景

当前 `BatteryProvider` 将 IOKit 的 `kIOPSIsChargingKey` 直接映射到状态模型的 `isCharging`。这个键只表示电池当前是否正在吸收电量：当 Mac 已接入电源适配器、但因电量较高或优化充电而暂不增加电量时，它可能仍为 `false`。因此面板会出现 `Power Adapter + Charging No`，与产品希望表达的“当前由适配器供电”不一致。

## 目标

- 将面板中的 `Charging` 字段定义为“当前是否由电源适配器供电”。
- 适配器接入但电池暂未增加电量时，显示 `Charging Yes`。
- 电池供电时显示 `Charging No`。
- 无法判断供电来源时保持未知，不伪造 Yes/No。
- 缩短常规兜底采样延迟，同时保留 IOPowerSources 的事件通知。

## 方案

### 数据流

`BatteryProvider` 继续从同一个 IOPowerSources 描述读取供电来源，并将来源映射为 `PowerSource`：

- `kIOPSACPowerValue` → `.powerAdapter`，`isCharging = true`
- `kIOPSBatteryPowerValue` → `.battery`，`isCharging = false`
- 其他或缺失值 → `.unknown`，`isCharging = nil`

`kIOPSIsChargingKey` 不再作为面板 `Charging` 字段的权威来源。这样面板、组合图标颜色和统一快照使用同一套“适配器供电”语义；字段名称暂不改动，以保持现有界面和本地化稳定。

### 刷新策略

将 `SystemStatusStore` 的默认 `samplingIntervalNanoseconds` 从 2 秒改为 1 秒。电池的 IOPowerSources 通知继续作为主要的事件驱动刷新机制，1 秒采样只负责兜底和纠正可能遗漏或延迟的状态变化。现有可注入采样间隔保留，测试无需改变其时间控制方式。

### 错误处理

- 供电来源明确为适配器或电池时，返回对应的布尔值。
- 供电来源未知时，`PowerSource` 返回 `.unknown`，`isCharging` 返回 `nil`，由 UI 按现有可选值规则处理。
- 电池容量不可用、无内置电池和其他 Provider 失败行为不变。

## 测试

增加纯逻辑回归测试，验证：

1. 适配器供电且 `kIOPSIsChargingKey == false` 时，状态仍为 `isCharging == true`。
2. 电池供电时状态为 `isCharging == false`。
3. 未知供电来源时状态为 `isCharging == nil`。

保留现有 BatteryProvider、SystemStatusStore 和 UI 行为测试，并通过构建/测试验证 1 秒默认值不会破坏已有的可注入采样间隔。

## 范围外

- 不接入充电上限、能源模式或任何电源控制能力。
- 不修改 `Power Source` 的显示文案。
- 不增加新的 UI 字段或重构 Provider 接口。
