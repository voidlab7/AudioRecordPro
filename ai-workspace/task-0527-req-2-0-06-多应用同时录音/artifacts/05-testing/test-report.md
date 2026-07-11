# REQ-2.0-06 多应用同时录音 — 测试报告

> 版本: V1.0 | 创建: 2026-05-31 | 测试负责人: 矩
> 报告类型: 本地测试（编译验证 + 静态检查 + 手动测试指引）

---

## 1. 编译验证结果

| 项目 | 结果 |
|------|------|
| 编译命令 | `xcodebuild -project AudioRecordMac.xcodeproj -scheme AudioRecordMac -configuration Debug build` |
| 编译状态 | ✅ **BUILD SUCCEEDED** |
| 错误 | 无 |
| 警告 | 2 个（与本次改动无关，为 pre-existing Warning） |
| 编译时间 | — |

**结论：编译通过，无阻塞性错误。可以进入手动测试阶段。**

---

## 2. 代码静态检查结果

### 2.1 ✅ 已验证通过的项

| 检查项 | 预期 | 实际 | 结果 |
|--------|------|------|------|
| `TracksView.swift` tracksStack.distribution | `.fillEqually` | ✅ 第 61 行：`tracksStack.distribution = .fillEqually` | PASS |
| `IndustrialCheckboxView` 组件存在 | 自定义 Checkbox 组件 | ✅ 第 881 行：`final class IndustrialCheckboxView: NSView` | PASS |
| `IndustrialCheckboxView` 集成到进程行 | Checkbox 显示在每行左侧 | ✅ 第 979 行：`let checkbox = IndustrialCheckboxView()` | PASS |
| 多选逻辑 — 点击选中/取消 | 点击行可以切换选中状态 | ✅ 第 393-400 行：使用 `firstIndex` + `remove` / `append` | PASS |
| 5 个限制逻辑 | 第 6 个选中时拒绝 | ✅ 第 396 行：`guard self.selectedPIDs.count < 5 else { ... }` | PASS |
| `TracksView.createTracksFromSelection` 多轨道 | 支持 `selectedProcesses.prefix(5)` | ✅ 第 513 行：`for process in selectedProcesses.prefix(5)` | PASS |
| 空状态引导 | 未选中时显示引导 | ✅ `emptyStateContainer` 配置完整，文案"请选择音频源" | PASS |
| 轨道等分高度 | `fillEqually` + 去掉固定高度 | ✅ `createTrackRow` 中注释："去掉固定高度，由 tracksStack 的 NSStackViewDistribution 等分控制" | PASS |

### 2.2 ⚠️ 发现的问题

#### Bug #1：Toast 提示未实现

- **严重度**：P0
- **影响测试用例**：TC-04（超过 5 个拒绝）
- **描述**：`SidebarView.swift` 第 48 行定义了 `onSelectionLimitReached` 回调，第 397 行在超过 5 个时触发了回调。但是 `MainWindowView.swift` 中**没有注册这个回调的处理函数**，导致超过 5 个选中时**没有任何 Toast 提示**。
- **预期行为**：第 6 个选中时弹出 Toast "最多同时录制 5 个音源"
- **实际行为**：静默拒绝（第 6 个不被选中），但用户不知道为什么
- **修复建议**：在 `MainWindowView.swift` 中注册 `sidebarView.onSelectionLimitReached` 回调，调用 Toast 提示

```swift
// 建议在 MainWindowView.setupView() 中添加：
sidebarView.onSelectionLimitReached = { [weak self] _ in
    guard let self = self else { return }
    self.showToast(message: "最多同时录制 5 个音源")
}
```

#### Bug #2：录制中侧边栏未锁定

- **严重度**：P0
- **影响测试用例**：TC-13（录制中 Checkbox 锁定）、TC-14（录制中底部提示）
- **描述**：`MainWindowView.swift` 的 `switchToMode(.recording)` 方法（第 447 行）中，只锁定了 `editToolbarView`，但**没有锁定 `sidebarView`**。用户在录制中仍然可以点击侧边栏的 Checkbox 切换选中状态。
- **预期行为**：录制中 Checkbox 半透明、不可点击、光标变禁止图标
- **实际行为**：录制中仍然可以点击 Checkbox 切换选中
- **修复建议**：
  1. 在 `SidebarView` 中添加 `setSelectionEnabled(_:)` 方法
  2. 在 `switchToMode(.recording)` 中调用 `sidebarView.setSelectionEnabled(false)`
  3. 在 `switchToMode(.idle)` 中调用 `sidebarView.setSelectionEnabled(true)`

#### Bug #3：`selectedPIDs` 类型与测试计划不一致

- **严重度**：P2（文档问题）
- **描述**：测试计划 `TEST-PLAN.md` 中写的是 `selectedPIDs: Set<pid_t>`，但实际代码使用的是 `selectedPIDs: [pid_t]`（数组）。数组也可以正确工作，但去重逻辑需要用 `firstIndex` 而不是 `contains`。
- **影响**：不影响功能，但测试计划中的自动化测试代码示例无法编译。
- **修复建议**：同步更新测试计划中的类型描述，或改为 `Set<pid_t>` 以获得 O(1) 查找性能。

---

## 3. 手动测试清单

> ⚠️ **注意**：以下测试用例需要你手动在 App 中操作验证。我已完成了编译验证和代码静态检查，下面是给你准备的测试指引。

### 3.1 侧边栏多选（需要手动测试）

| ID | 用例 | 操作步骤 | 预期结果 | 状态 |
|----|------|---------|---------|------|
| TC-01 | 单选进程 | 点击 Chrome 行 | Chrome 被选中，Checkbox 勾选 | ⏳ 待手动测试 |
| TC-02 | 多选进程（2个） | 点击 Chrome 行，再点击 Music 行 | 两个均被选中 | ⏳ 待手动测试 |
| TC-03 | 多选进程（5个） | 依次选中 5 个进程 | 5 个均被选中，轨道区显示 5 条轨道 | ⏳ 待手动测试 |
| TC-04 | 超过 5 个拒绝 | 已选中 5 个，尝试点第 6 个 | ⚠️ **已知 Bug #1：无 Toast 提示**，但第 6 个应不被选中 | ⏳ 待手动测试 |
| TC-05 | 取消选中 | 选中后再点同一行 | 取消选中 | ⏳ 待手动测试 |
| TC-06 | 麦克风独立选择 | 点击麦克风行 | 不影响进程选择 | ⏳ 待手动测试 |
| TC-07 | 选中态视觉 | 观察选中行 | 左侧蓝色竖条 + 背景高亮 | ⏳ 待手动测试 |

### 3.2 多轨道显示（需要手动测试）

| ID | 用例 | 操作步骤 | 预期结果 | 状态 |
|----|------|---------|---------|------|
| TC-08 | 1 条轨道铺满 | 选中 1 个进程，开始录制 | 轨道高度铺满 | ⏳ 待手动测试 |
| TC-09 | 2 条轨道等分 | 选中 2 个进程，开始录制 | 2 条轨道各占约 50% | ⏳ 待手动测试 |
| TC-10 | 5 条轨道等分 | 选中 5 个进程，开始录制 | 5 条轨道等分，每条最小高度 ≥80px | ⏳ 待手动测试 |
| TC-11 | 轨道颜色区分 | 选中多个进程观察 | 颜色不同 | ⏳ 待手动测试 |
| TC-12 | 轨道选中态 | 点击某条轨道 | 高亮显示 | ⏳ 待手动测试 |

### 3.3 录制中锁定（需要手动测试）

| ID | 用例 | 操作步骤 | 预期结果 | 状态 |
|----|------|---------|---------|------|
| TC-13 | 录制中 Checkbox 锁定 | 录制中尝试点击 Checkbox | ⚠️ **已知 Bug #2：未锁定**，预期应不可点击 | ⏳ 待手动测试 |
| TC-14 | 录制中底部提示 | 录制中观察侧边栏底部 | 应显示"录制中，不可修改" | ⏳ 待手动测试 |

### 3.4 断开状态（需要手动测试）

| ID | 用例 | 操作步骤 | 预期结果 | 状态 |
|----|------|---------|---------|------|
| TC-15 | 应用退出断开 | 录制中退出 Chrome | 轨道显示"已断开" | ⏳ 待手动测试 |
| TC-16 | 断开态不可播放 | 选中断开轨道点播放 | 播放按钮置灰 | ⏳ 待手动测试 |

### 3.5 空状态（需要手动测试）

| ID | 用例 | 操作步骤 | 预期结果 | 状态 |
|----|------|---------|---------|------|
| TC-17 | 0 个选中空状态 | 未选中任何音源观察主界面 | 显示箭头引导 + "请选择音频源" | ⏳ 待手动测试 |
| TC-18 | 选中后空状态消失 | 选中 Chrome | 空状态消失，显示轨道区 | ⏳ 待手动测试 |

---

## 4. 测试结论

### 4.1 编译验证
- ✅ 编译成功，无 Error
- ⚠️ 2 个 pre-existing Warning（与本次改动无关）

### 4.2 代码静态检查
- ✅ 8 个检查项通过
- ❌ 3 个 Bug 需要修复（其中 2 个 P0）

### 4.3 是否可以进入 06-summary 阶段

**暂定：需要先修复 2 个 P0 Bug 后再手动测试。**

建议修复顺序：
1. **Bug #1**（P0）：实现 Toast 提示 — 预估 15 分钟
2. **Bug #2**（P0）：录制中锁定侧边栏 — 预估 30 分钟
3. **Bug #3**（P2）：同步测试计划文档 — 预估 5 分钟

修复后重新编译，然后进行完整的手动测试。

---

## 5. 附录：静态检查详细日志

```
编译命令：
xcodebuild -project AudioRecordMac.xcodeproj -scheme AudioRecordMac -configuration Debug build

关键文件检查：
- SidebarView.swift (47.84 KB, 1169 行)
  ✅ IndustrialCheckboxView 组件 (第 881 行)
  ✅ 多选逻辑 (第 393-403 行)
  ✅ 5 个限制 (第 396 行)
  ⚠️ onSelectionLimitReached 未注册处理 (第 48 行定义，第 397 行触发)

- TracksView.swift (23.54 KB, 532 行)
  ✅ fillEqually 分布 (第 61 行)
  ✅ 空状态引导 (第 78-130 行)
  ✅ 多轨道创建 (第 508-542 行)

- MainWindowView.swift (32.71 KB, 807 行)
  ✅ SidebarView 集成 (第 25 行声明，第 162 行设置 delegate)
  ⚠️ switchToMode 未锁定 sidebar (第 447 行)
```
