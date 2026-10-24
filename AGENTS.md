# Repository guidance

Before changing this repository, read `CONTRIBUTING-AI.md` and the linked guidance relevant to the task.

Before planning or implementing the personal health-log milestones, follow `docs/project/README.md` to the shared specification and M1 plan.

## 代码探索与协作

- 实现前，若任务跨多个模块且需要梳理至少两条可独立调查的调用链，本项目授权主 agent 主动启动两个只读探索子 agent 并行调查。工具、并发或用量限制导致委派不可用时，由主 agent 继续并说明降级。
- 按独立问题划分调查边界，例如界面状态流与账户/API 数据流；每个子 agent 返回文件与符号位置、调用链、受影响测试及模拟、需求遗漏。默认由主 agent 统一修改代码、整合结果并运行验证。
- 普通文件定位和单次内容搜索由主 agent 使用 `rg` 完成：先限定路径，再检索内容；独立查询批量执行。修改公共组件或共享逻辑时，同时检索调用方、测试包装器及相关模拟。
- 先通过针对性测试，再完成评审和修复，变更稳定后执行规定的全量检查。全量检查由主 agent 统一调度；后续修改影响已验证行为时，重跑相应检查。

## Agent skills

### Issue tracker

Issues and specs live in this fork's GitHub Issues. Read `docs/agents/issue-tracker.md` before reading or writing tickets.

### Triage labels

Use the five default triage labels. Read `docs/agents/triage-labels.md` before classifying or labelling tickets.

### Domain docs

Single-context: root `CONTEXT.md` and `docs/adr/`. Read `docs/agents/domain.md` before exploring domain terms or architecture decisions.
