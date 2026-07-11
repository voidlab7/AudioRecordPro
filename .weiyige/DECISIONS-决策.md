# DECISIONS / 决策

> Project: `audio_record_mac`  
> Last updated: 2026-06-10  
> Purpose: 记录已做出的项目决策，避免反复争论和上下文丢失。

---

## Decision Log / 决策日志

### 2026-06-10 — 初始化项目上下文协议

- Decision / 决策：项目内 `.weiyige/` 降级为项目上下文，不再复制全局角色定义。
- Reason / 理由：角色方法论只保留在全局 `AIAgent/.weiyige/`，项目内只保存 PROJECT / WORKFLOW / DECISIONS / MEMORY / TASKS。
- Impact / 影响：以后使用 `PM_枢(project=audio_record_mac)` 这类运行实例，而不是为每个项目维护一套角色文件。

---

## Template / 模板

### YYYY-MM-DD — [决策标题]

- Decision / 决策：
- Context / 背景：
- Options / 备选：
- Reason / 理由：
- Impact / 影响：
- Revisit / 何时复盘：
