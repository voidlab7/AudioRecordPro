# 工程架构方案 — 音频文件编辑视图联动

**作者**: 矩·架构  
**日期**: 2026-05-25  
**版本**: v1.0  
**状态**: 待审查

---

## 一、问题分析

### 当前架构瓶颈

```
用户选中文件 → sidebarViewDidSelectFile → mainWindowViewDidSelectRecordedFile
    → enterEditor(file:)
        → 销毁旧 EditorViewController
        → 新建 EditorViewController(file:)
        → loadAudio() [耗时操作：读取文件、解码PCM、渲染波形]
        → showEditor(editorView) [alpha 淡入]
```

**核心问题**：
1. **每次切换文件都重新加载音频** — 大文件(>50MB)加载耗时可达 2-5 秒
2. **无状态保持** — 切换后丢失缩放比例、选区、工具选择
3. **过渡不流畅** — `hideEditor()` + `showEditor()` 有明显闪烁
4. **编辑器与播放互斥** — `enterEditor` 强制 `stopPlayback()`

---

## 二、架构方案

### 2.1 核心思路：Editor Session Pool

引入 **EditorSessionManager** 管理编辑器会话池，实现文件切换时的状态保持和快速恢复。

```
┌──────────────────────────────────────────────────────┐
│  MainViewController                                   │
│  ┌────────────────────────────────────────────────┐  │
│  │  EditorSessionManager (NEW)                     │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐          │  │
│  │  │Session A│ │Session B│ │Session C│ (LRU 池)  │  │
│  │  │file_a   │ │file_b   │ │file_c   │           │  │
│  │  │buffer ✓ │ │buffer ✓ │ │buffer ✓ │           │  │
│  │  │state ✓  │ │state ✓  │ │viewport✓│           │  │
│  │  └─────────┘ └─────────┘ └─────────┘          │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
│  ┌────────────────┐       ┌────────────────────┐     │
│  │  SidebarView    │ ──→  │  EditorContainerView│     │
│  │  (文件列表)     │       │  (动画切换容器)     │     │
│  └────────────────┘       └────────────────────┘     │
└──────────────────────────────────────────────────────┘
```

### 2.2 新增类设计

#### EditorSessionManager

```swift
class EditorSessionManager {
    /// LRU 缓存池（最多保留 3 个 session，超出则释放最早未使用的）
    private var sessions: [URL: EditorSession] = [:]
    private var accessOrder: [URL] = []
    private let maxSessions = 3
    
    /// 获取或创建 session
    func session(for file: RecordedFileInfo) -> EditorSession
    
    /// 关闭指定 session（释放内存）
    func closeSession(for url: URL)
    
    /// 关闭所有 session
    func closeAll()
    
    /// 内存压力时释放非活跃 session
    func handleMemoryWarning()
}
```

#### EditorSession（从 EditorViewController 重构提取）

```swift
class EditorSession {
    let file: RecordedFileInfo
    
    // 音频数据（加载后缓存）
    var audioBuffer: AVAudioPCMBuffer?
    var audioFormat: AVAudioFormat?
    var audioAsset: AudioAsset?
    
    // 视图状态（切换时保持）
    var viewportState: ViewportState  // 缩放比例、滚动位置
    var selectionRange: Range<Int>?   // 选区
    var activeTool: EditorTool        // 当前工具
    
    // 编辑历史
    let editHistory: EditHistory
    var hasUnsavedChanges: Bool
    
    // 生命周期
    var isLoaded: Bool
    var lastAccessTime: Date
}
```

#### ViewportState（状态快照）

```swift
struct ViewportState {
    var zoomLevel: Double      // 缩放比例
    var scrollOffset: Double   // 滚动偏移
    var playheadPosition: Double  // 播放头位置
}
```

### 2.3 文件切换流程（优化后）

```
用户选中文件 B（当前在编辑文件 A）
    │
    ▼
┌─ EditorSessionManager.session(for: fileB) ─┐
│  ├─ 命中缓存？ → 直接返回 session（已有 buffer）
│  └─ 未命中？ → 创建新 session + 异步 loadAudio()
└─────────────────────────────────────────────┘
    │
    ▼
┌─ 保存当前状态 ──────────────────────────────┐
│  sessionA.viewportState = currentViewport    │
│  sessionA.selectionRange = currentSelection  │
│  sessionA.activeTool = currentTool           │
└──────────────────────────────────────────────┘
    │
    ▼
┌─ 动画过渡 ──────────────────────────────────┐
│  Cross-dissolve (200ms):                     │
│    editorView A → alpha: 0                   │
│    editorView B → alpha: 1                   │
│  完成后移除 A 的 view（但 session 保留）      │
└──────────────────────────────────────────────┘
    │
    ▼
┌─ 恢复 B 的状态 ─────────────────────────────┐
│  viewport → sessionB.viewportState           │
│  selection → sessionB.selectionRange         │
│  tool → sessionB.activeTool                  │
└──────────────────────────────────────────────┘
```

### 2.4 文件信息展示

在 `EditorNavigationBar` 中增加文件信息区域：

```
┌─────────────────────────────────────────────────────────────┐
│  [← 返回]  文件名.wav  │  3:42  │  48kHz·32bit·stereo  │  12.4MB  │
└─────────────────────────────────────────────────────────────┘
```

当前 `EditorNavigationBar` 已有 `setFileName()` 方法，需扩展为完整的文件信息展示。

---

## 三、修改范围

### 3.1 新增文件

| 文件 | 职责 |
|------|------|
| `Sources/Editor/EditorSessionManager.swift` | 编辑器会话池管理 |
| `Sources/Editor/EditorSession.swift` | 单个编辑会话（状态+数据） |

### 3.2 修改文件

| 文件 | 修改内容 |
|------|---------|
| `MainViewController.swift` | `enterEditor` 改用 SessionManager，增加切换逻辑 |
| `MainWindowView.swift` | `showEditor` 支持 cross-dissolve 动画 |
| `EditorViewController.swift` | 重构：分离 session 数据和 view 控制 |
| `EditorNavigationBar.swift` | 扩展文件信息显示（时长、采样率、大小） |

### 3.3 不修改的文件

- `RecordedFilesView.swift` — 选择事件已正确冒泡
- `SidebarView.swift` — delegate 链路已完整
- 编辑命令文件(TrimCommand 等) — 不受影响

---

## 四、关键设计决策

### DR-001: 会话池大小

- **选择**: 最多缓存 3 个 session（LRU 淘汰）
- **理由**: macOS 桌面场景内存相对充裕；3 个 session 覆盖"文件 A/B 来回切换"的典型场景
- **替代方案**: 仅缓存 1 个（太少，无法覆盖典型场景）；无限制（内存爆炸）
- **可逆性**: 5/5，常量可随时调整

### DR-002: 动画方案

- **选择**: Cross-dissolve（200ms）
- **理由**: 比 hide+show 更流畅；比滑动切换更轻量；macOS 原生感强
- **替代方案**: 滑动切换（增加实现复杂度，DAW 类软件一般不用）
- **可逆性**: 5/5

### DR-003: EditorViewController 重构策略

- **选择**: 渐进式重构 — 先提取 EditorSession 管理数据，EditorViewController 保留 view 控制
- **理由**: 风险可控，不需要一次性重写整个编辑器
- **替代方案**: 完全重写（风险高，工期长）
- **可逆性**: 4/5

---

## 五、性能预算

| 指标 | 目标 | 备注 |
|------|------|------|
| 缓存命中时文件切换 | < 100ms | 仅状态恢复 + 动画 |
| 首次加载短文件(< 1min) | < 500ms | PRD P0 要求 |
| 首次加载长文件(> 5min) | < 2000ms | tile 模式异步加载 |
| Session 内存占用 | < 150MB/session | 基于 48kHz/32bit/stereo/5min 计算 |

---

## 六、风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 多 session 内存压力 | 中 | 高 | 监听 `didReceiveMemoryWarning`，释放非活跃 session |
| 编辑器重构引入 bug | 中 | 中 | 分步重构，每步有测试覆盖 |
| 切换时未保存编辑丢失 | 低 | 高 | 切换前检查 hasUnsavedChanges，提示保存 |

---

## 七、开发分步计划

| 步骤 | 内容 | 预计耗时 |
|------|------|---------|
| Step 1 | 新增 `EditorSession` + `EditorSessionManager` | 0.5 天 |
| Step 2 | 重构 `MainViewController.enterEditor` 使用 SessionManager | 0.5 天 |
| Step 3 | 实现 cross-dissolve 动画（修改 `MainWindowView.showEditor`） | 0.5 天 |
| Step 4 | 扩展 `EditorNavigationBar` 文件信息显示 | 0.5 天 |
| Step 5 | 状态保持：viewport + tool + selection | 1 天 |
| Step 6 | 内存管理 + LRU 淘汰 | 0.5 天 |
| Step 7 | 集成测试 + 边界情况处理 | 1 天 |

**总计**: 4.5 天（PRD 估计 5 天开发，吻合）

---

## 📤 交接块（Handoff）

- **来源**: 矩·架构
- **阶段**: 设计
- **产出类型**: 架构设计文档
- **产物文件**: `ai-workspace/audio-file-editor-linkage/artifacts/03-design/eng-review.md`
- **状态**: 通过
- **关键决策**:
  1. 会话池大小: LRU 3 个 session
  2. 动画方案: Cross-dissolve 200ms
  3. 重构策略: 渐进式，先提取 EditorSession
- **开放问题**:
  1. 是否需要支持"文件被外部修改"时自动刷新 session？（建议 V1.1 做）
- **下游建议**: 交铸·开发按 Step 1-7 顺序实现
- **阻塞项**: 无
