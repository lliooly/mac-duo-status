# 插电状态能源模式能力检测修复设计

## 背景

能源模式 helper 使用 `pmset -g cap` 检测设备是否支持 Low Power 和 High Power。
该命令的能力区块标题会跟随当前供电来源变化：使用电池时为
`Capabilities for Battery Power:`，连接电源适配器时为
`Capabilities for AC Power:`。

当前 `PMSetPowerModeParser.parseCapabilities` 只识别电池标题。helper 在插电状态下
初始化时会把合法的 AC 能力输出判定为不可解析，进而公开空能力集合。界面因此把能源
模式降级为只读的“暂时不可用”。

## 方案

让能力解析器把以下两个标题视为同一种能力区块起点：

- `Capabilities for Battery Power:`
- `Capabilities for AC Power:`

区块内部的严格校验维持不变：仍只接受单个能力区块，并继续验证
`lowpowermode`、`highpowermode` 行的格式。不会放宽未知输出、重复标题或畸形数据的
处理。

helper、XPC 接口、状态模型和 SwiftUI 展示层均不需要修改。修复后无论 helper 在电池
还是插电状态下启动，都会公开相同的设备能源模式能力；当前作用域仍由现有电池状态
决定。

## 测试

为 `PMSetPowerModeParser` 增加 AC Power 能力标题的单元测试，验证 Low Power 和
High Power 都能被识别。保留既有 Battery Power 测试和畸形输出测试，确保严格解析
行为没有回退。

完成实现后运行项目测试套件。成功标准是：插电状态下 Automatic、Low Power 和
High Power 选项正常显示并可用，电池状态下行为保持不变。
