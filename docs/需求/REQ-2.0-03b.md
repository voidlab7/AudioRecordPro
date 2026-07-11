# REQ-2.0-03b 视图改造 + 绘制迁移

## 版本：V2.0 | 优先级：P0 | 状态：⬜ 待开发

> 父需求：REQ-2.0-03 剪映式虚拟时间线音频轨道波形展示
> 依赖：REQ-2.0-03a（数据模型 + Tile 引擎）
> 预估工时：1 天

---

## 1. 一句话需求

将 `EditorWaveformView` 从全局 `allSamples` 绘制模型迁移到 visible tiles 绘制模型，改造 `EditorViewController` 使大文件走 tile 模式，实现滚动/缩放后按需请求 tiles 并流畅绘制。

---

## 2. 目标用户故事

### US-01：打开长录音不卡死

> 作为录制了 1 小时以上音频的用户，我想打开录音后编辑器不要卡死，并能看到轨道概览。

### US-02：左右滑动定位

> 作为处理长录音的用户，我想在时间线上左右滑动到任意时间段，并看到该视口范围内的波形。

### US-03：缩放查看细节

> 作为需要精细剪辑的用户，我想放大某个时间段后看到更高精度的波形，而不是被整段压缩过的模糊波形误导。

### US-04：避免粗到细跳变

> 作为在轨道上查找剪辑点的用户，我不希望同一区域的波形从粗略形状突然变成另一种精细形状。

---

## 3. 改造范围

### 3.1 EditorViewController 改造

| 改动点 | 说明 |
|--------|------|
| `loadAudio()` 方法 | 大文件（>60s 或 >50MB）走 tile 模式，仅构建 `AudioAsset` 不全量读 PCM |
| 短文件兼容 | ≤60s 文件保留现有 `loadAudio(from: buffer)` 路径 |
| 编辑 buffer 延迟加载 | 波形展示不依赖编辑 buffer，解耦展示与编辑 |

**判定逻辑：**

```swift
let useTileMode = duration > 60 || fileSize > 50 * 1024 * 1024
```

### 3.2 EditorWaveformView 改造

| 改动点 | 说明 |
|--------|------|
| 新增 `useTileMode` 属性 | 区分 tile 模式和传统 allSamples 模式 |
| 新增 `loadAudioAsset(_:)` 方法 | 初始化 tile provider，设置 delegate |
| 新增 `requestVisibleTiles()` 方法 | 滚动/缩放后请求当前视口 tiles |
| 新增 `drawWaveformTiles()` 方法 | 按 tile 的时间范围映射到像素绘制 min/max 振幅 |
| 新增 `drawFallback()` / `drawSkeleton()` | 目标 LOD 未就绪时的占位显示 |
| 改造 `scrollWheel` | 滚动后调用 `requestVisibleTiles()` |
| 改造 `zoom` 逻辑 | 缩放后重新选择 LOD 并请求 tiles |
| 保留 `loadAudio(from:)` | 短文件和编辑后刷新的兼容路径 |

### 3.3 绘制逻辑

**核心变更：从全局数组比例映射 → 按真实时间映射到 x 坐标**

```text
旧：sampleIndex = allSamples.count * visibleStartTime / totalDuration
新：x = timeToPixel(peak.time) → 基于 viewport.pixelsPerSecond
```

**绘制流程：**

```text
draw(rect)
  ├── useTileMode == false → drawWaveformBars() (原逻辑)
  └── useTileMode == true
       ├── 有 currentTiles → drawWaveformTiles()
       │    └── 对每个 tile 的每个 peak:
       │         ├── peakTime = tile.sourceStartTime + i * peakDuration
       │         ├── x = timeToPixel(peakTime)
       │         ├── 绘制 min/max 上下振幅柱
       │         └── 颜色/透明度基于振幅和选区状态
       └── 无 tile → drawSkeleton()
```

---

## 4. 交互要求

### 4.1 打开文件

1. 初始化 `AudioAsset`（仅读元数据，不读 PCM）
2. 初始化 `WaveformTileProvider`
3. Fit All：设置 `visibleStartTime = 0`，`visibleDuration = totalDuration`
4. 请求当前视口 tiles
5. 首屏显示 skeleton，tiles 就绪后淡入

### 4.2 左右滑动

```text
scroll delta pixels
  → deltaTime = deltaPixels / pixelsPerSecond
  → visibleStartTime += deltaTime
  → requestVisibleTiles()
```

要求：
- 预取范围：左右各 `visibleDuration * 0.5`
- 快速滑动时旧请求可取消
- 滑动不阻塞 UI

### 4.3 缩放

```text
anchorX → anchorTime = pixelToTime(anchorX)
  → 更新 visibleDuration / pixelsPerSecond
  → 保持 anchorTime 在缩放前后仍位于鼠标位置
  → 重新选择 LOD
  → requestVisibleTiles()
```

要求：
- 缩放锚定鼠标所在时间点
- 播放头、选区、标记位置不漂移
- LOD 切换时重新请求目标 LOD tiles

### 4.4 未加载区域显示

| 场景 | 显示 |
|------|------|
| 目标 LOD 已加载 | 正常绘制 |
| 目标 LOD 未加载，低 LOD 有缓存 | 淡化显示低 LOD fallback（alpha 0.4） |
| 无任何可用 tile | 显示 skeleton loading stripe |
| tile 正在生成 | 不阻塞滚动和缩放 |
| 生成失败 | 当前 tile 显示失败占位，不影响其他 tile |

---

## 5. 受影响文件

| 文件 | 改动类型 |
|------|----------|
| `EditorWaveformView.swift` | 重大改造：新增 tile 绘制路径 |
| `EditorViewController.swift` | 中等改造：大文件走 tile 模式 |

---

## 6. 验收标准

### 6.1 大文件打开

- [ ] 打开 1 小时以上录音，App 不无响应
- [ ] 打开 1GB 级录音，编辑器不因波形展示全量分配 PCM
- [ ] 首屏可在 3s 内显示 Fit All 概览或占位
- [ ] 波形加载失败不导致编辑器崩溃

### 6.2 左右滑动

- [ ] 用户可在长录音轨道上左右滑动
- [ ] 滑动到任意时间段后，当前视口能请求并显示对应 tiles
- [ ] 快速滑动时旧请求不覆盖新视口
- [ ] 视口外 tile 生成不阻塞当前滚动

### 6.3 缩放

- [ ] 缩放以鼠标位置为 anchor
- [ ] 缩放后鼠标下的时间点保持稳定
- [ ] 缩放后根据 `pixelsPerSecond` 自动切换 LOD
- [ ] 放大到秒级视图时，不继续使用整段低精度 `allSamples`
- [ ] 缩放过程播放头、选区、标记不漂移

### 6.4 波形绘制

- [ ] `EditorWaveformView` 不再依赖单一全局 `allSamples` 作为唯一数据源
- [ ] 每个 peak 按真实时间映射到 x 坐标
- [ ] 波形使用 `min` / `max` 绘制上下振幅
- [ ] 目标 LOD 未加载时显示 skeleton 或低置信度 fallback
- [ ] tile 完成后只更新相关显示，不造成整页闪烁

### 6.5 回归

- [ ] 短录音（≤60s）仍能正常显示完整波形（走原路径）
- [ ] 播放头显示和 seek 正常
- [ ] 选区拖拽仍正常
- [ ] 编译通过

---

## 7. 下游建议

### 给绘（设计）

- skeleton 加载态的视觉样式（建议低调条纹动画）
- 低 LOD fallback 的淡化方式（建议 alpha 0.4 + 轻微模糊）
- tile 淡入过渡动画时长（建议 150ms）

### 给铸（开发）

- 先改造 `EditorViewController` 的 `loadAudio()` 分流逻辑
- 再在 `EditorWaveformView` 新增 tile 绘制路径
- 最后接入滚动/缩放触发 `requestVisibleTiles()`
- 保留 `allSamples` 路径不删除，短文件仍走原逻辑

### 给鉴（QA）

- 测试 5 分钟、30 分钟、1 小时、1GB+ 文件的打开
- 测试快速左右滑动（模拟用户快速拖动）
- 测试连续缩放（滚轮快速滚动）
- 测试缩放时播放头和选区稳定性
- 测试短文件（≤60s）行为不变
