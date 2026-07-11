
## 日志文件位置（2026-07-11 确认）

App 启用了沙盒（`app-sandbox=true`），`FileManager.urls(for: .documentDirectory)` 返回的是**沙盒容器**路径，
而非 `~/Documents/`。

**日志路径**：
```
~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/audiorecord_YYYY-MM-DD.log
```

**实时查看**：
```bash
tail -f ~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/audiorecord_$(date +%Y-%m-%d).log
```

**Logger 类**：`AudioRecordKit/Sources/Utils/Logger.swift`
- 使用沙盒内的 `FileManager.urls(for: .documentDirectory)`
- 自动创建 `AudioRecordings/Logs/` 子目录
- NSLog 输出进系统统一日志（Console.app 可查）

**⚠️ 注意**：
- 非沙盒构建时路径为 `~/Documents/AudioRecordings/Logs/`
- `entitlements` 中的 `app-sandbox=true` 决定最终路径
