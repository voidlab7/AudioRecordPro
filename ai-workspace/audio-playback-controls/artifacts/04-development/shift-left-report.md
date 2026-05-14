# 左移检查报告 — audio-playback-controls

## 实现范围

任务：实现播放、暂停、选择不同音频并播放的能力。

## 改动文件

- `AudioRecordApp/Sources/Controllers/MainViewController.swift`
- `AudioRecordApp/Sources/Views/RecordedFilesView.swift`（仅使用既有选择回调，无直接修改）
- `AudioRecordApp/Sources/Views/SidebarView.swift`
- `AudioRecordApp/Sources/Views/MainWindowView.swift`
- `AudioRecordApp/Sources/Views/ControlPanelView.swift`
- `AudioRecordApp/Sources/Views/TracksView.swift`

## 关键实现

1. 文件选择链路：
   - `RecordedFilesView` 选中文件
   - `SidebarView` 转发 `sidebarViewDidSelectFile`
   - `MainWindowView` 转发 `mainWindowViewDidSelectRecordedFile`
   - `MainViewController` 保存为 `selectedPlaybackFile`

2. 播放状态管理：
   - `MainViewController` 使用独立 `AVAudioPlayer` 管理播放，不再依赖录制器活跃列表。
   - 同一文件播放中再次点击播放按钮会暂停。
   - 暂停后再次点击会继续。
   - 选择不同文件会停止当前播放并切换目标。

3. UI 反馈：
   - `ControlPanelView` 支持播放暂停态显示。
   - `TracksView` 新增播放面板，显示文件名、当前时间、总时长、进度条和播放控制按钮。

## 左移检查

命令：

```bash
./build-app.sh
```

结果：

```text
✅ 构建完成！
📂 应用位置: /Users/voidzhang/Documents/workspace/audio_record_mac/build/AudioRecordMac.app
```

结论：Swift 编译与 App 打包通过。
