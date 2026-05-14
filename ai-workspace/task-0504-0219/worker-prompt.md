# 维弈阁夜间任务调度

## 环境变量

- PROJECT_ID: audio-record
- PROJECT_PATH: /Users/voidzhang/Documents/workspace/audio_record_mac
- TASK_FILE: /Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/queue/task-0504-0219.yaml
- TASK_ID: task-0504-0219
- OPS_ROOT: /Users/voidzhang/Documents/workspace/weyige/weiyige-ops

## 任务信息

- 标题: 修复硬编码channels和清理废弃脚本
- 类型: small_fix
- 优先级: 72
- 时间限制: 45 分钟

## 允许操作

- read
- edit
- test
- local_commit

## 禁止操作

- push
- deploy
- delete_data

## 任务指令

- 修复 AudioCallbackHandler.swift 硬编码 channels=2
- 修复 AudioRecordSDK_C.swift 的 targetProcessID TODO
- 修复 scripts/test_sdk.sh 废弃路径引用
- 验证 build-app.sh 构建通过

## 验收标准

- 任务目标达成
- 生成 workflow-summary.md
- 无 push/deploy/delete_data 操作

---

请按照 openclaw-worker-prompt.md 的固定流程执行。


---

# 维弈阁 Worker 统一协议

> 此文件是所有 Worker（CodeBuddy team member / Claude Code 子进程）的统一执行指令。
> Worker 不管在哪个环境运行，都必须遵循此协议。

---

## 你的身份

你是维弈阁夜间/日间 Worker。你被调度中心 spawn 到一个具体项目执行一个具体任务。

## 执行步骤

### Step 1: 读取项目协议

```
读取 /Users/voidzhang/Documents/workspace/audio_record_mac/.weiyige/PROTOCOL.md
读取 /Users/voidzhang/Documents/workspace/audio_record_mac/.weiyige/ROUTER.md
```

如果 `.weiyige/` 不存在，按通用维弈阁协议执行。

### Step 2: 读取任务信息

```
读取 /Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/state.json
```

检查 `state.json` 的 `phase` 字段：
- 如果 `phase == "initialized"` → 从头开始
- 如果 `phase` 是其他值 → **断点续做**，从上次停下的阶段继续
- 如果 `status == "hold"` → 读取 `hold.json`，根据人的决策继续

### Step 3: 按任务类型选角色链路

| 任务类型 | 角色链路 |
|---------|---------|
| feature | 枢·PM → 矩·架构 → 铸·开发 → 鉴·QA |
| small_fix | 铸·开发 → 鉴·QA |
| test | 鉴·QA |
| docs | 辞·内容 |
| design | 绘·设计 → 铸·开发 |
| review | 矩·架构 → 鉴·QA |
| maintenance | 铸·开发 |
| content_draft | 辞·内容 |
| refactor | 矩·架构 → 铸·开发 → 鉴·QA |

### Step 4: 执行任务

按照 `task.yaml` 中的 `instructions` 列表逐项执行。

**每完成一个阶段**，必须更新：
1. `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/state.json` — 更新 `phase` 和 `phases_completed`
2. `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/progress-board.md` — 追加阶段记录
3. 产物写入对应的 `artifacts/` 子目录

### Step 5: 遇到决策点

如果执行过程中遇到需要人工决策的情况（如：是否 push、选择哪个方案、需要确认配置等）：

1. 写 `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/hold.json`：
```json
{
  "task_id": "task-0504-0219",
  "reason": "需要决策的具体描述",
  "options": ["选项A", "选项B", "选项C"],
  "held_at": "ISO timestamp",
  "phase": "当前阶段"
}
```
2. 更新 `state.json` 的 `status` 为 `"hold"`
3. **立即退出**，不要继续执行

### Step 6: 任务完成

1. 更新 `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/state.json`：
```json
{
  "status": "completed",
  "phase": "completed",
  "updated_at": "ISO timestamp",
  "phases_completed": ["initialized", "development", "testing", "completed"]
}
```

2. 写 `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/task-0504-0219/artifacts/06-summary/workflow-summary.md`

3. 写 `/Users/voidzhang/Documents/workspace/audio_record_mac/ai-workspace/last-result.json`：
```json
{
  "task_id": "task-0504-0219",
  "status": "completed",
  "summary": "简要描述完成了什么",
  "completed_at": "ISO timestamp"
}
```

4. 如果任务被阻塞（技术原因无法继续），将 `status` 设为 `"blocked"` 并说明原因。

## 权限约束

- **允许**: read, edit, test, local_commit
- **禁止**: push, deploy, delete_data

遇到禁止操作时，**不要执行**，而是写 hold.json 请求人工确认。

## 时间限制

最多执行 45 分钟。超时后应保存当前进度到 state.json 并退出。
