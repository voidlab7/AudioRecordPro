# REQ-2.0-06 多应用同时录音 — 测试计划

> 版本: V1.0 | 创建: 2026-05-30 | 状态: 待执行
> 测试负责人: 矩 | 评审人: 绘、枢

---

## 1. 测试范围

本次测试覆盖 REQ-2.0-06 多应用同时录音功能的：
- 侧边栏多选逻辑（Checkbox 交互）
- 多轨道显示（1~5 条轨道等分高度）
- 录制中锁定状态
- 超过 5 个音源限制
- 应用退出断开状态
- 空状态引导

---

## 2. 测试用例

### 2.1 侧边栏多选

| ID | 用例 | 前置条件 | 操作步骤 | 预期结果 | 优先级 |
|----|------|---------|---------|---------|--------|
| TC-01 | 单选进程 | 侧边栏显示进程列表 | 点击 Chrome 行 | Chrome 被选中，Checkbox 勾选，其他行未选中 | P0 |
| TC-02 | 多选进程（2个） | 侧边栏显示进程列表 | 点击 Chrome 行，再点击 Music 行 | Chrome 和 Music 同时被选中，Checkbox 均勾选 | P0 |
| TC-03 | 多选进程（5个） | 侧边栏显示 ≥5 个进程 | 依次选中 5 个不同进程 | 5 个进程均被选中，轨道区显示 5 条轨道 | P0 |
| TC-04 | 超过 5 个拒绝 | 已选中 5 个进程 | 尝试点击第 6 个进程 | 第 6 个不被选中，触发 Toast 提示"最多同时录制 5 个音源" | P0 |
| TC-05 | 取消选中 | Chrome 已选中 | 再次点击 Chrome 行 | Chrome 取消选中，Checkbox 未勾选 | P0 |
| TC-06 | 麦克风独立选择 | 侧边栏显示麦克风选项 | 点击麦克风行 | 麦克风被选中/取消，不影响进程选择 | P1 |
| TC-07 | 选中态视觉 | Chrome 已选中 | 观察 Chrome 行 | 左侧蓝色竖条显示，背景高亮 | P1 |

### 2.2 多轨道显示

| ID | 用例 | 前置条件 | 操作步骤 | 预期结果 | 优先级 |
|----|------|---------|---------|---------|--------|
| TC-08 | 1 条轨道铺满 | 只选中 Chrome | 开始录制 | 轨道区只有 1 条轨道，高度铺满轨道区 | P0 |
| TC-09 | 2 条轨道等分 | 选中 Chrome + Music | 开始录制 | 2 条轨道高度相等，各占约 50% | P0 |
| TC-10 | 5 条轨道等分 | 选中 5 个进程 | 开始录制 | 5 条轨道高度相等，每条最小高度 ≥80px | P0 |
| TC-11 | 轨道颜色区分 | 选中多个进程 | 观察轨道波形颜色 | 每条轨道颜色不同（蓝/青/紫/绿/橙） | P1 |
| TC-12 | 轨道选中态 | 显示多条轨道 | 点击某条轨道 | 该轨道左侧蓝色竖条 + 背景高亮 | P1 |

### 2.3 录制中锁定

| ID | 用例 | 前置条件 | 操作步骤 | 预期结果 | 优先级 |
|----|------|---------|---------|---------|--------|
| TC-13 | 录制中 Checkbox 锁定 | 正在录制 | 尝试点击侧边栏 Checkbox | Checkbox 半透明，不可点击，光标变禁止图标 | P0 |
| TC-14 | 录制中底部提示 | 正在录制 | 观察侧边栏底部 | 显示"录制中，不可修改"提示 | P1 |

### 2.4 断开状态

| ID | 用例 | 前置条件 | 操作步骤 | 预期结果 | 优先级 |
|----|------|---------|---------|---------|--------|
| TC-15 | 应用退出断开 | 正在录制 Chrome 音频 | 退出 Chrome | 对应轨道显示"已断开"状态，波形变虚线，红色警告图标 | P0 |
| TC-16 | 断开态不可播放 | 某轨道已断开 | 选中该轨道，点击播放 | 播放按钮置灰，不可点击 | P1 |

### 2.5 空状态

| ID | 用例 | 前置条件 | 操作步骤 | 预期结果 | 优先级 |
|----|------|---------|---------|---------|--------|
| TC-17 | 0 个选中空状态 | 未选中任何音源 | 观察主界面 | 显示箭头引导空状态，文案"请选择音频源" | P1 |
| TC-18 | 选中后空状态消失 | 未选中任何音源 | 选中 Chrome | 空状态消失，显示轨道区 | P1 |

---

## 3. 编译验证

### 3.1 编译命令

```bash
cd /Users/voidzhang/Documents/workspace/audio_record_mac
xcodebuild -project AudioRecordApp.xcodeproj -scheme AudioRecordApp -configuration Debug build
```

### 3.2 预期结果

- 编译成功，无 Error
- 允许 Warning（但不应引入新的逻辑 Warning）
- 重点关注：
  - `SidebarView.swift` 中 `selectedPIDs: Set<pid_t>` 类型是否正确
  - `TracksView.swift` 中 `tracksStack.distribution = .fillEqually` 是否生效
  - `IndustrialCheckboxView` 是否正确显示在 `IndustrialProcessRowView` 中

---

## 4. 自动化测试（可选）

```swift
// 测试用例示例：selectedPIDs 多选逻辑
func testMultiSelectPIDs() {
    let sidebar = SidebarView()
    sidebar.selectedPIDs = []
    
    // 选中第一个进程
    sidebar.selectProcess(pid: 1001)
    XCTAssertEqual(sidebar.selectedPIDs.count, 1)
    
    // 选中第二个进程
    sidebar.selectProcess(pid: 1002)
    XCTAssertEqual(sidebar.selectedPIDs.count, 2)
    
    // 取消选中
    sidebar.deselectProcess(pid: 1001)
    XCTAssertEqual(sidebar.selectedPIDs.count, 1)
}
```

---

## 5. 测试进度跟踪

- [ ] TC-01 单选进程
- [ ] TC-02 多选进程（2个）
- [ ] TC-03 多选进程（5个）
- [ ] TC-04 超过 5 个拒绝
- [ ] TC-05 取消选中
- [ ] TC-06 麦克风独立选择
- [ ] TC-07 选中态视觉
- [ ] TC-08 1 条轨道铺满
- [ ] TC-09 2 条轨道等分
- [ ] TC-10 5 条轨道等分
- [ ] TC-11 轨道颜色区分
- [ ] TC-12 轨道选中态
- [ ] TC-13 录制中 Checkbox 锁定
- [ ] TC-14 录制中底部提示
- [ ] TC-15 应用退出断开
- [ ] TC-16 断开态不可播放
- [ ] TC-17 0 个选中空状态
- [ ] TC-18 选中后空状态消失
- [ ] 编译验证通过

---

## 6. 测试报告输出

测试完成后，输出报告到：
`ai-workspace/task-0527-req-2-0-06-多应用同时录音/artifacts/05-testing/test-report.md`

报告内容：
1. 测试用例通过率
2. 发现的 Bug 列表（附截图）
3. 编译 Warning 清单
4. 建议修复项
5. 是否可以进入 06-summary 阶段
