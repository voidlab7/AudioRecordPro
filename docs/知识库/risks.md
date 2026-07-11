# 风险与 QA 知识库

> 更新时间：2026-06-28（根据实际代码校准，V1.1 编辑器已全部实现）  
> 来源：从 `../AudioRecordApp知识库.md` 的代码事实差异、状态机、风险清单、QA 路径拆分。  
> 范围：技术债、代码事实与文档差异、状态边界、QA 必测路径。

## 当前代码事实与文档差异

| 主题 | 文档描述 | 代码事实 | 处理建议 |
|---|---|---|---|
| V1.1 编辑器 | ❌ ~~需求/README.md 仍显示未完成~~ | 代码中已有完整 `EditorViewController` + 5条Command + 撤销重做 + Session Pool + 磁盘缓存 | ✅ 已修正（2026-06-28） |
| V2.0 REQ-2.0-05 | ❌ ~~录制完成后自动进入编辑器标为 ⬜~~ | `handleRecordingComplete` 中 0.3s 后调用 `enterEditor(file:)` | ✅ 已修正为 ✅ |
| UI 主布局 | 文档主张编辑器独立工作区 | ✅ 已用三态 `ViewMode`（idle/recording/editing）实现，TrackPanel+Waveform 同一行 | 文档已更新 |
| 轨道板 | REQ-2.0-01 写左侧轨道板 | ✅ 已实现 TrackPanelView（左侧 60px）+ WaveformView（中间弹性）+ LevelMeterCardView（右侧 80px） | 符合设计 |
| 编辑器高级特性 | ❌ ~~文档未记录~~ | Session Pool、Cross-dissolve 切换、WaveformDiskCache、TimelineViewport 均已实现 | ✅ 已补充到 tech.md |
| 混录比例 | 文档写 100% + 100% | 代码 MixedAudioRecorder 是 0.6 + 0.4 | ⚠️ 统一产品规格和代码 |
| 录音格式 | 文档默认 M4A，可选 WAV | 代码中 AudioFormat 支持 .m4a/.wav，通过 settings 传递正确格式参数 | 设置页已打通 |
| MP3 导出 | 提供 MP3 导出选项 | 代码通过系统 ffmpeg 调用 `libmp3lame -b:a 192k` 转码，是需要外部依赖的**真实 MP3** | 外部 ffmpeg 依赖需在产品页说明 |
| macOS 版本 | 文档最低 14.4 | 代码有 `#available(macOS 14.4, *)` 守卫 + 无 fallback 的优雅降级 | 产品页建议写 14.4+ |
| 编辑器文件限制 | ❌ ~~文档未记录~~ | 500MB 文件 / 30分钟 / 1GB PCM 限制 | ✅ 已补充到 tech.md |
| Multi-process 录制 | 文档提及 | 代码实现独立多进程录制（每个进程独立 Tap）+ MultiProcessLevelView | 功能存在但未完整打通 UI |
| 撤销重做 | 文档写"待开发" | EditHistory（Command 模式，最大 20 步）已实现 | ✅ 已修正 |

## 录制状态机

```text
idle
  → preparing
  → recording
  → stopping
  → idle

任意状态 → error
playing 与 recording 互斥
editing 与 recording 互斥
```

## 关键互斥规则

| 场景 | 规则 |
|---|---|
| 录制中 | 禁止进入编辑器、禁止切换音源、禁止删除正在写入文件 |
| 编辑中 | 禁止录制、禁止播放同一文件、切换文件需确认未保存 |
| 播放中 | 点击录制前应停止播放 |
| 文件不存在 | 从列表移除并提示 |
| 权限被撤销 | 停止录制，保存已录内容，提示用户重新授权 |
| 进程退出 | 停止录制，保存已录内容，提示目标进程退出 |
| 磁盘不足 | 录制前检查，录制中监控，空间不足时停止并保存 |

## QA 必测路径

| 路径 | 用例 |
|---|---|
| 系统音频 | YouTube 播放 → 录制 → 回放清晰 |
| 进程录制 | 只录 Chrome，其他 App 通知声不混入 |
| 混录 | 系统音频 + 麦克风均存在，音量比例可接受 |
| 长录制 | 连续录制 4 小时无崩溃 |
| **编辑** | **裁剪 / 静音裁剪 / 标准化 / 淡入淡出 / 撤销重做** ✅ 代码已实现，需回归测试 |
| **编辑器预览** | **编辑器中实时播放预览效果** |
| **编辑器文件切换** | **Cross-dissolve 切换不同文件不丢失状态** |
| **会话池** | **多次进出编辑器保持视口/选区** |
| 大文件 | >500MB 文件编辑不崩溃，有明确提示 |
| 损坏文件 | 列表展示 / 编辑加载 / 导出均不崩溃 |
| 权限拒绝 | 不闪退，有明确引导 |
| 录制中退出 | 停止并保存或恢复临时文件 |
| **录制→编辑器过渡** | **录制完成后自动进入编辑器，选区和游标正确** |

## P0 风险

| 风险 | 影响 | 建议 |
|---|---|---|
| App Store 审核风险 | Private TCC Framework / CoreAudio 动态符号可能被拒 | 上架前做合规审查，准备非 MAS 分发方案 |
| ~~主界面 UI 方向错误~~ | ~~卡片式布局~~ → ✅ 已解决（V2.0 轨道+轨道板模式） | — |
| ~~录制 / 编辑状态混杂~~ | ~~误操作~~ → ✅ 已解决（三态 ViewMode） | — |
| MP3 导出外部依赖 | ffmpeg 未安装时导出失败 | 首次导出时引导安装 ffmpeg，或提供 dmg 内打包 ffmpeg |
| 多进程录制 UI 未完整 | MultiProcessLevelView 已写但侧边栏交互待完善 | REQ-2.0-06 统一 |

## P1 风险

| 风险 | 影响 | 建议 |
|---|---|---|
| `MainViewController` 过大（~1900行） | 维护困难 | V1.2 拆分 RecordingCoordinator / PlaybackCoordinator / FileCoordinator |
| 右声道电平未完整接入 | L/R 显示不真实 | 打通 `MainWindowView.updateLevels(left:right:)` 数据流 |
| Mute / Solo 伪功能 | 降低信任 | 未接音频前隐藏或 disabled |
| 编辑器大文件内存压力 | 大文件崩溃（已有 500MB/30min/1GB 硬限制 + DiskCache） | 风险降低——已有分层防御 |
| ~~文档状态滞后~~ | ~~团队决策混乱~~ → ✅ 本次已全面校准 | 定期同步即可 |

## 文档维护规则

1. 产品需求变更：更新 `product.md` 和 `../需求/`。
2. UI 方向变更：更新 `../设计/设计规范.md` 和 `../设计/`。
3. 底层录制变更：更新 `tech.md`。
4. 实现状态变化：更新本文件的"代码事实与文档差异"。
5. QA 发现关键 bug：同步加入本文件和 `../缺陷/`。
6. 不再新增多个互相冲突的 UI 草案；当前方向统一沉淀到 `../设计/设计规范.md` 和 `../设计/`。
