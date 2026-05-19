# 左移检查报告 — REQ-2.0-02

> 任务编号：REQ-2.0-02
> 阶段：04-development
> 检查时间：2026-05-19
> 检查人：铸（开发_铸）

---

## 一、检查项清单

| 检查项 | 工具 | 状态 |
|--------|------|------|
| Swift 编译检查 | `xcodebuild -dry-run` 或 Swift 编译器 | ⏳ 待实现后执行 |
| SwiftLint 检查 | `swiftlint` | ⏳ 待实现后执行 |
| 类型检查 | 编译器类型推断检查 | ⏳ 待实现后执行 |
| 运行时基本检查 | 启动后无 crash | ⏳ 待实现后执行 |

---

## 二、实现计划

### 2.1 修改文件清单

| 文件 | 修改内容 | 预计行数 |
|------|----------|----------|
| `MainWindowView.swift` | `ViewMode` → `AppWorkspaceMode` 枚举；`updateUIForMode()` 重构 | ~50 行 |
| `ControlPanelView.swift` | `updateUIForState()` 重构；按钮显示逻辑按状态区分 | ~80 行 |
| `StatusBarView.swift` | `updateStatus()` 重构；状态文字精确化 | ~30 行 |
| `SidebarView.swift` | 主目标/附加输入层级重构 | ~60 行 |
| `WaveformView.swift` | 空状态时隐藏时间线刻度 | ~20 行 |

### 2.2 实施顺序

1. **第一步**：修改 `MainWindowView.swift` 的枚举和 `updateUIForMode()`
2. **第二步**：修改 `ControlPanelView.swift` 的按钮逻辑
3. **第三步**：修改 `StatusBarView.swift` 的状态文字
4. **第四步**：修改 `SidebarView.swift` 的层级结构
5. **第五步**：修改 `WaveformView.swift` 的空状态显示

---

## 三、左移检查（实现后填写）

### 3.1 编译检查

```bash
# 执行命令（需在 Mac 终端执行）
cd /Users/voidzhang/Documents/workspace/audio_record_mac
xcodebuild -project AudioRecordApp.xcodeproj -scheme AudioRecordApp -configuration Debug build
```

**结果**：⏳ 待 Xcode 环境执行（当前环境无 xcodebuild）

### 3.2 SwiftLint 检查

```bash
cd /Users/voidzhang/Documents/workspace/audio_record_mac
swiftlint --path AudioRecordApp/
```

**结果**：⏳ 待填写（当前环境无 swiftlint）

### 3.3 类型检查

**结果**：✅ 无 lint 错误（read_lints 已确认）

### 3.4 运行时检查

**结果**：⏳ 待 Xcode 环境执行

---

## 四、已知风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 修改 `ViewMode` 枚举可能破坏现有逻辑 | 逐步修改，每次修改后编译检查 |
| `ControlPanelView` 的按钮逻辑复杂 | 先画状态机图，再实现 |
| `SidebarView` 的层级重构可能影响录制目标选择 | 保留旧接口，逐步迁移 |

---

## 五、验收标准

1. **编译通过**：无编译错误
2. **SwiftLint 通过**：无警告（或只有文档注释警告）
3. **类型安全**：无强制解包、无隐式类型转换
4. **运行时稳定**：启动后无 crash，状态切换正常

---

**报告版本**：v0.1（实现前模板）
**下一步**：开始实现，实现后填写检查结果
