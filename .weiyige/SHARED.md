# 维弈阁共享知识（Weiyige Shared Knowledge）

> 版本: v1.0 | 创建: 2026-05-13 | 状态: 生效中

所有角色的公共规则和模板。角色 SOUL.md 中通过引用（如「详见 SHARED.md §三档模式」）避免重复加载。

---

## §1 两档模式

| 模式 | 判定标准 | 是否需要 init-task | 行为 |
|------|---------|-------------------|------|
| **问答模式** | 不会 `write_to_file` | ❌ 不需要 | 解释代码、回答问题、分析建议 |
| **工作模式** | 会 `write_to_file` / `replace_in_file` | ✅ 必须 | 写代码、写文档、审查报告、设计方案 |

**唯一判定标准**：接下来会不会写文件。会 = 工作模式（必须 init-task），不会 = 问答模式。

---

## §2 完成前自检（交接前必查）

每个角色完成工作前必须验证：

- [ ] **产出落盘** — 产出文件可通过 `read_file` 读取
- [ ] **交接块就绪** — 交接块已准备（含下游 Agent 建议）
- [ ] **记忆更新** — 有值得记录的经验/教训/发现已写入 `memory/`
- [ ] **范围守护** — 没有越权修改不在方案范围内的文件
- [ ] **计算型检查** — Lint/类型检查/测试等已通过 `execute_command` 实际执行（适用角色：矩、铸、鉴）

---

## §3 职责三分法

每个角色的职责划分为三层：

| 分类 | 含义 |
|------|------|
| **主 Owned** | 该角色独占负责的工作 |
| **协作** | 需要与其他角色配合的工作 |
| **不做** | 明确禁止做的事（越权防线） |

---

## §4 CLI 使用规范（v2 闭环同步）

- **禁止直接 `write_to_file` state.json / project-status.json** — 必须走 `weiyige-cli` 命令
- **写文件前必须 init-task** — 只要会 `write_to_file` / `replace_in_file`，必须先创建任务。纯问答不需要
- 每次 CLI 命令都**自动同步 project-status.json**（ops dashboard 实时更新）

### CLI 路径

按优先级尝试：
1. `weiyige-cli`（如已加入 PATH）
2. `node /Users/voidzhang/Documents/workspace/weyige/weiyige-ops/bin/cli/weiyige-cli.mjs`（绝对路径）
3. 若都不可用，提示用户确认 CLI 安装路径

### 核心命令

| 场景 | 命令 | 说明 |
|------|------|------|
| 启动任务 | `weiyige-cli init-task <id> --title "标题"` | 创建 state.json + running/ lock + ops 同步 |
| 阶段更新 | `weiyige-cli update-phase <id> --phase X --status Y --agent Z` | 依赖检查 + 更新 + ops 同步 + progress-board |
| 交接 | `weiyige-cli handoff <id> --from 铸 --to 鉴 --phase X --artifact <path>` | 产物验证 + JSONL 日志 + 状态推进 + ops 同步 |
| 门禁检查 | `weiyige-cli gate <id> --phase X` | Layer 0 确定性检查（前置/产物/格式） |
| 产物验证 | `weiyige-cli artifact <id> --path <path>` | 文件存在 + 非空 + 统计 |
| 完成任务 | `weiyige-cli finish-task <id>` | 前置检查 + ops 同步 + running 清理 + git commit |
| 查看状态 | `weiyige-cli status [task_id]` | 项目概况 / 任务详情 |

### 关键规则

1. state.json 写入前自动 `validateState`，非法数据拒绝写入
2. `update-phase --status in_progress` 自动检查前置阶段已完成/跳过，**不允许跳阶段**
3. `handoff` 验证产物文件存在且非空，**不存在则拒绝交接**
4. `finish-task` 前置检查：phase 完成性 + running/ 残留 + queue→done 移动

---

## §5 Git 规范

- 不主动执行 `git push` —— 需用户确认
- 不执行 `git push --force` / `git reset --hard` 等破坏性操作
- `finish-task` 默认自动 `git commit`（可 `--no-commit` 跳过）
- 创建功能分支前必须 `git stash` 无关修改

---

## §6 环境与安全

- 涉及 `git push`、`rm -rf`、SCP 部署 → **不自动执行，提醒用户确认**
- 敏感信息（密码、Token、API Key）不写入代码或 git 仓库
- 服务器操作需确认 IP 地址和目标环境

---

## §7 版本管理元信息格式

所有角色文件的头部使用统一的版本管理格式：

```markdown
<!-- Version: vX.X | Created: YYYY-MM-DD | Updated: YYYY-MM-DD -->
<!-- Changelog: ... -->
```

尾部元信息：

```markdown
**命名由来**：X=...
**团队定位**：...
**核心输出/方法论**：...
```

---

## §8 交接块协议

Agent 之间的信息传递通过交接块（Handoff Block）：

```markdown
## 交接块
- **来源**: [角色名]
- **目标**: [下游角色名]
- **产出路径**: ai-workspace/{task_id}/artifacts/{阶段}/
- **摘要**: [一句话总结]
- **建议下游关注**: [重点事项]
```

---

*共享知识的目标：一处定义，多处引用，消除 13 个角色间的重复加载。*
