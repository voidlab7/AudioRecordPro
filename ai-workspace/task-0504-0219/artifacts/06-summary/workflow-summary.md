# Task: 修复硬编码channels和清理废弃脚本

## 任务信息
- **Task ID**: task-0504-0219
- **类型**: small_fix
- **优先级**: 72
- **状态**: completed
- **完成时间**: 2026-05-04 02:30

## 修复内容

### 1. 修复硬编码 channels=2（AudioCallbackHandler.swift 第73行）

**问题**: `globalAudioCallback` 中声道数硬编码为 `2`，注释标注 TODO。

**修复方案**:
- 在 `AudioCallbackHandler` 类中新增 `channelCount` 属性（默认值 2，保持向后兼容）
- 新增 `setChannelCount(_ count: Int)` 方法
- 全局回调函数改为读取 `handler.channelCount` 而非硬编码值
- 在 `CoreAudioProcessTapRecorder` 的两个录制路径（C API / Swift API）中，创建音频文件时从 `audioFormat.mChannelsPerFrame` 读取实际声道数并调用 `setChannelCount()`

**改动文件**:
- `AudioRecordKit/Sources/Core/ProcessTap/AudioCallbackHandler.swift` — 新增属性和方法，回调函数使用动态值
- `AudioRecordKit/Sources/Core/ProcessTap/CoreAudioProcessTapRecorder.swift` — 两处设置声道数

### 2. 修复 AudioConstraints 支持 targetProcessID（AudioRecordSDK_C.swift 第210行）

**问题**: `AudioRecord_StartWithProcess` 函数接收 `pid` 参数但未使用，TODO 标注需扩展 AudioConstraints。

**修复方案**:
- 在 `AudioConstraints` 结构体中新增 `targetProcessID: Int32?` 可选属性
- 更新初始化器支持 `targetProcessID` 参数
- `AudioRecord_StartWithProcess` 直接将 `pid` 传入 constraints，消除 `_ = pid` 的 dead code

**改动文件**:
- `AudioRecordKit/Sources/API/AudioConstraints.swift` — 新增属性和初始化参数
- `AudioRecordKit/Sources/CAPI/AudioRecordSDK_C.swift` — 使用 targetProcessID

### 3. 修复 test_sdk.sh 废弃路径

**问题**: 脚本引用已废弃的 `src/` 目录，该目录已不存在（代码已迁移至 `AudioRecordKit/Sources/`）。

**修复方案**:
- `SRC_DIR` 从 `$ROOT_DIR/src` 改为 `$ROOT_DIR/AudioRecordKit/Sources`
- 所有源文件路径按新目录结构更新：
  - `Models/` → `Core/Models/`
  - `Recorder/` → `Core/Protocols/` + `Core/Recorders/`
  - `ProcessTapRecorder/` → `Core/ProcessTap/`
  - `AudioRecordSDK/` → `API/`
- 移除已不存在的测试文件引用（`Tests/SDKTestRunner.swift`, `Tests/TestMain.swift`）

**改动文件**:
- `scripts/test_sdk.sh`

### 4. 构建验证

- 运行 `bash build-app.sh` — **构建成功通过**
- 编译无错误、无警告（针对修改的部分）
