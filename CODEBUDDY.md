# audio_record_mac（录音 App / Loocap 路文）— 项目入口

> 2026-09-20 重写：进入 Loop 时代。本文件是项目入口，CodeBuddy 每次会话自动读取。

## 一句话

macOS 录音 App（Loocap 路文，2026-10-11 前旧名 Tapture）：系统音频内录 + 麦克风录制 + 转写 + 剪映式轻编辑。唯一开发方式 = **Loop 开发循环**。

## 核心文件地图

| 文件 | 角色 |
|---|---|
| `docs/LOOP.md` | 循环宪法（状态机/三条规则/刹车/运转机制） |
| `.codebuddy/rules/loop-protocol.md` | 协议自动加载版（每次会话强制在场） |
| `TODOS.md` | 需求池 = **唯一状态真相**（单子/验收标准/状态/证据） |
| `roles/Tab/AGENT.md` | 执行者人格（PM+测试+研发一体） |
| `docs/需求/<单号>-*.md` | 每张单的规格文档（编号规范见 `docs/LOOP.md` §十一；2026-10-11 起新单用 FEAT/FIX/UI/INFRA-NNN，存量 REQ-*.md 不回改） |
| `e2e/testcases/` | 自验用例 |

总纲（通用方法论，跨项目复用）：`AIAgent/research/LoopEngineering/LOOP-ENGINEERING-指导方针.md`

## 快速指令

| 老板说 | 做什么 |
|---|---|
| 「跑 loop」/「继续跑 loop」 | 读 `TODOS.md` → 取最高优先级 todo 单 → 交付（实现→自验→修≤3轮）→ 写状态 → 继续下一张，直到池空或 blocked |
| 「Tab」/「让 Tab 看看」 | 进入录音 App 专属角色（见 `roles/Tab/AGENT.md`） |
| 单子未带验收标准 | 先起草标准请老板签，**不开工** |

## 项目角色：Tab

录音 App 专属 PM+测试+研发。身份、能力、铁律见 `roles/Tab/AGENT.md`。

## 铁律

1. **不轻信 UI**：功能验证必须落盘硬验证（afinfo/wave 解析、文件存在/编码/时长）
2. **根因闭环**：修 bug = 日志证据 + 代码行号 + 修复 + 回归用例
3. **内容红线**：WorkBuddy / IMA / 腾讯内部技术方案严禁出现在任何对外内容中
4. **Loop 纪律**：单子带标准 / 做完必自验 / 问题必回池 / 单间必重读池（详见 `docs/LOOP.md`）
