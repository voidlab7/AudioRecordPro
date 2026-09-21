# UX 可观测性与交互测试方案

> 2026-09-19 落地 v1。目标：App 自带"行车记录仪"，测试/排障/行为分析共用一份结构化事件流，
> computer-use 从"主力测试"降级为"最终验收"。

## 一、核心思想（第一性原理）

交互测试 = **输入注入 → 状态观测 → 断言**。computer-use 慢的根因是观测走"截图+VLM"
（慢、贵、误判）。本方案把观测从像素下沉到 App 内部数据，把断言从 VLM 下沉到代码。

## 二、五层事件模型

每行 JSONL 落盘到沙盒 `Documents/AudioRecordings/Logs/UXEvents/uxevents_*.jsonl`：

| 层 | 回答的问题 | 采集方式 |
|---|---|---|
| `lifecycle` | App 何时启停 | 自动（AppDelegate） |
| `input` | 用户物理上做了什么（点击/键盘/滚动） | 自动（全局 local monitor，零埋点） |
| `action` | 用户想干什么（意图） | 动作分发点埋点 |
| `state` | UI 变成了什么样 | 状态转换埋点，可附视图树快照 |
| `module` | 功能有没有正常运转 | start/ok/fail + 耗时 |
| `artifact` | 最终产物对不对 | 文件创建/删除/大小（落盘硬验证） |

## 三、已埋点位（v1）

- **录制链路**：start_recording(action) → Recording.start/stop(module，带时长) →
  Recording.captured(module，采样率/声道) → Encrypt.write(module ok/fail) →
  arlock_created(artifact) / Recording.fail(module)
- **播放链路**：select_file(action) → Playback.start(ok/fail) → pause/resume(action) →
  Playback.finish(module)
- **导出链路**：export_card_opened(action) → export_start(action+module) →
  Export.done(ok/fail) → export_file_created(artifact) / export_cancelled(action)
- **编辑器**：enter_editor(action) → editor_shown(state+视图树快照) →
  Editor.save(module) → editor_hidden(state+快照)
- **侧边栏**：tab_changed(state)、select_record_target(action)、mix_audio_toggle(action)
- **文件管理**：FileList.load(module，count)、rename(ok/fail)、delete_file(action)+file_deleted(artifact)
- **可靠性**：Recovery.restore(ok/fail)+recovered_arlock_created(artifact)、Recording.autostop(module)
- **菜单/快捷键**：AppDelegate 六个 menu action 统一埋点

## 四、使用指南

```bash
# 回放最新会话时间线
python3 scripts/ux_replay.py

# 只看输入和模块事件
python3 scripts/ux_replay.py --type input,module

# 操作统计（哪些按钮点得多、哪些模块失败）
python3 scripts/ux_replay.py --stats

# 落盘 markdown 报告
python3 scripts/ux_replay.py --out timeline.md
```

事件文件路径（沙盒）：
`~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/UXEvents/`

注意：App 每次启动会 clearLogFiles()，UXEvents 目录也会被清（与现有日志语义一致，每次会话从 0 开始）。

## 五、断言模式（测试怎么用）

自动化测试不再看图，而是断言事件序列。导出测试 = 三行断言：

```python
events = load_jsonl()
assert has(events, action="export_start")
assert has(events, module="Export.done", ok=True)
assert has(events, artifact="export_file_created", size>0)
```

录制测试 = 断言 `Recording.stop` 出现且 elapsed 与产物时长一致（afinfo 交叉验证）。

## 六、关键事实与边界

1. **AX 语义点击（System Events click / AXPress）不产生 NSEvent**，input 层捕获不到；
   computer-use 的 CGEvent/HID 注入点击会被捕获（需注入方有辅助功能授权）。
   AX 路径由 action 埋点兜住，两层互补无盲区。
2. 滚动事件 300ms 节流，避免高频淹没日志。
3. 视图树快照只在状态转换点（编辑器进出）记录，不随每次点击记录。

## 七、Roadmap

- [ ] 交互回归脚本（脚本驱动操作 → 断言 JSONL，秒级回归）
- [ ] 自动 UI 变化 diff（点击后视图树 hash 对比，异常自动记录）
- [ ] crash breadcrumb（信号处理器 flush 最后 N 条事件，随崩溃上报）
- [ ] 编辑器子操作埋点（裁剪/分割/撤销重做）
