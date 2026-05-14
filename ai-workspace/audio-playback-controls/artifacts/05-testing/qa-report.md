# QA 报告 — audio-playback-controls

## 验证范围

- 选择不同录音文件
- 播放 / 暂停 / 继续
- 停止播放
- 播放进度 UI
- 编译通过

## 已执行验证

| 项目 | 结果 | 说明 |
|---|---|---|
| 构建检查 | ✅ 通过 | `./build-app.sh` 成功生成 `build/AudioRecordMac.app` |
| 文件选择链路静态检查 | ✅ 通过 | `RecordedFilesView → SidebarView → MainWindowView → MainViewController` 已打通 |
| 播放状态 UI 静态检查 | ✅ 通过 | `TracksView` 已显示文件名、时间、进度和控制按钮 |
| 播放完成回调 | ✅ 通过 | `AVAudioPlayerDelegate` 处理完成和解码错误 |

## 待人工回归

由于当前未启动 GUI 自动化播放测试，建议人工验证：

1. 打开 App，进入 `Saved Files`。
2. 选择文件 A，点击 `TracksView` 或底部控制面板的播放按钮。
3. 播放中再次点击播放按钮，确认暂停。
4. 再次点击播放按钮，确认继续播放。
5. 点击停止，确认状态回到 ready。
6. 选择文件 B，确认播放目标切换为 B。
7. 播放结束后，确认状态显示播放完成，进度到终点。

## 结论

代码层面和构建检查通过。功能行为需要在真实音频文件环境下做一次人工回归。
