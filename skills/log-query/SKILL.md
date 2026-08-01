---
name: log-query
description: AudioRecordMac 日志查询与诊断技能。当用户请求查看日志、排查崩溃、分析窗口不显示、诊断权限问题、检查启动失败原因时使用。自动识别沙盒/非沙盒编译的日志目录差异。触发关键词：查看日志、日志在哪、log、crash、崩溃、闪退、窗口不显示、启动失败、权限问题、诊断、debug log。
---

# AudioRecordMac 日志查询与诊断 Skill

## 概述

此 Skill 为 AudioRecordMac 项目提供完整的日志查询和问题诊断能力。自动识别当前运行的是**沙盒编译**还是**非沙盒编译**，定位正确的日志目录并读取分析。

## 日志目录规则

### 核心代码位置

`AudioRecordKit/Sources/Utils/Logger.swift` 第 47-51 行：

```swift
private var logDirectory: URL {
    let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documentsPath.appendingPathComponent("AudioRecordings/Logs")
}
```

### 沙盒编译

当 `com.apple.security.app-sandbox = true` 时，`FileManager.default.urls(for: .documentDirectory, ...)` 自动解析为沙盒容器路径：

```
~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/
```

Bundle ID：`com.voidzhang.audio-record-mac`（定义在 `Info.plist`）

日志文件命名格式：`audiorecord_YYYY-MM-DD.log`

### 非沙盒编译

```
~/Documents/AudioRecordings/Logs/
```

日志文件命名格式相同。

### 如何判断当前编译类型

```bash
# 方法1：查看内置 App 的 entitlements
codesign -d --entitlements - build/AudioRecordMac.app 2>&1 | grep "app-sandbox"

# 方法2：检查沙盒容器是否存在
ls ~/Library/Containers/com.voidzhang.audio-record-mac/

# 方法3：查看日志目录路径（日志第一行会打印）
tail -1 ~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/audiorecord_*.log
```

### 构建时如何控制沙盒

`build-app.sh` 第 57-68 行的逻辑：

```bash
if [ -f "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" ]; then
  # 沙盒编译 → 带 entitlements 签名（当前默认）
  codesign --force --sign - --entitlements "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" ...
else
  # 非沙盒编译 → 不带 entitlements 签名
  codesign --force --sign - ...
fi
```

**切换为非沙盒编译**：删除或重命名 `AudioRecordApp/Resources/AudioRecordMac.entitlements`，然后重新 `bash build-app.sh`。

## 日志查询流程

### Step 1: 确认 App 是否在运行

```bash
ps aux | grep audio_record_mac | grep -v grep
```

如果无输出，说明 App 已退出，可直接读取历史日志。

### Step 2: 定位日志文件

并行检查两种路径（沙盒优先，因为当前默认是沙盒编译）：

```bash
# 沙盒路径（当前默认）
CONTAINER_LOG=~/Library/Containers/com.voidzhang.audio-record-mac/Data/Documents/AudioRecordings/Logs/

# 非沙盒路径
FALLBACK_LOG=~/Documents/AudioRecordings/Logs/

# 找到今天的日志
ls -la "$CONTAINER_LOG"audiorecord_$(date +%Y-%m-%d).log 2>/dev/null || \
ls -la "$FALLBACK_LOG"audiorecord_$(date +%Y-%m-%d).log 2>/dev/null
```

### Step 3: 读取日志

```bash
# 读取全部
cat "$LOG_PATH"

# 读取最后 50 行
tail -50 "$LOG_PATH"

# 搜索错误
grep -E "ERROR|FATAL|❌|💥" "$LOG_PATH"

# 搜索警告
grep -E "WARNING|⚠️" "$LOG_PATH"

# 按时间查看（带行数）
grep -n "" "$LOG_PATH" | tail -100
```

### Step 4: 使用系统日志补充

自定义 Logger 同时写入 `print()` (stdout) 和 `os_log()`，可以通过系统日志获取可能丢失的条目：

```bash
# 查看 subsystem "com.audiorecordmac" 的 os_log
log show --last 30m --predicate 'subsystem == "com.audiorecordmac"' --style compact

# 查看进程的所有日志
log show --last 30m --predicate 'process == "audio_record_mac"' --style compact

# 实时监控
log stream --predicate 'process == "audio_record_mac"' --style compact
```

### Step 5: 检查崩溃报告

```bash
# 查看最近的崩溃报告
ls -t ~/Library/Logs/DiagnosticReports/ | head -5 | grep audio_record
```

## 窗口不显示诊断流程

当出现「权限弹出了但窗口没展示」时，按以下步骤诊断：

### 诊断检查清单

1. **确认进程存活**
   ```bash
   ps aux | grep audio_record_mac | grep -v grep
   ```

2. **检查窗口状态**
   ```bash
   osascript -e 'tell application "System Events" to get {name, frontmost, visible, every window} of (first process whose name is "audio_record_mac")'
   ```

3. **读取今天日志（按流程 Step 3）**

4. **定位 breakpoint 位置**

   在日志中搜索关键标记：
   - `applicationDidFinishLaunching` — 应用启动
   - `createMainWindow` — 窗口创建路径
   - `contentViewController 设置完成` — 如果缺失说明 view 加载阶段崩溃
   - `first front` / `ensure front` / `兜底前置` — makeKeyAndOrderFront 调用
   - `主视图控制器开始加载` / `主视图控制器已加载` — viewDidLoad 生命周期

   **如果日志停在 `MainViewController 已创建` 后**，说明 `window.contentViewController = mainViewController` 触发 view 加载时发生了异常，导致 `createMainWindow()` 提前退出，未执行后续的 `makeKeyAndOrderFront`。

5. **复现并捕获异常**

   - 先切换到非沙盒编译（绕过可能的沙盒限制），看窗口是否正常显示
   - 注释掉 `viewDidLoad` 中的 `setupInitialState()` 调用，逐步定位异常点
   - 在 `createMainWindow()` 尾部添加 `print()` 或 `NSLog()` 打出完整调用栈

6. **常见根因**

   | 症状 | 可能原因 |
   |------|---------|
   | 进程运行但无窗口 | `makeKeyAndOrderFront` 未执行（异常提前退出） |
   | 窗口存在但不可见 | `isVisible=false` 且未调用 `orderFront` |
   | app 启动后立即退出 | 异常未处理导致 crash |
   | 权限弹窗后窗口不显示 | `requestAudioCapturePermissions()` 和 `createMainWindow()` 并发执行，后者异常退出 |

## 日志格式说明

每条日志的格式：

```
[yyyy-MM-dd HH:mm:ss.SSS] emoji [LEVEL] [fileName:line] function(): message
```

| 字段 | 说明 |
|------|------|
| 时间戳 | 精确到毫秒 |
| Emoji | ℹ️ INFO / ⚠️ WARNING / ❌ ERROR / 💥 FATAL / 🔍 DEBUG |
| LEVEL | 日志级别 |
| fileName:line | 源文件和行号 |
| function() | 调用方法名 |
| message | 日志内容 |

## 日志相关代码位置

| 文件 | 说明 |
|------|------|
| `AudioRecordKit/Sources/Utils/Logger.swift` | 日志实现 |
| `AudioRecordApp/Sources/App/AppDelegate.swift` | 启动流程 + 窗口创建 |
| `AudioRecordApp/Sources/Controllers/MainViewController.swift` | 主视图控制器（view loading 入口） |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | 主窗口视图（view hierarchy 组装） |
| `AudioRecordMac.entitlements` | 沙盒 entitlements 定义 |
| `build-app.sh` | 构建脚本（沙盒/非沙盒控制） |
| `Info.plist` | Bundle ID `com.voidzhang.audio-record-mac` |

## 日志生命周期

1. 启动时 `clearLogFiles()` 删除目录下所有旧日志（AppDelegate:47）
2. 当天日志按日期写入 `audiorecord_YYYY-MM-DD.log`
3. `cleanupOldLogs()` 自动清理 7 天前的日志（Logger:150）
4. 日志文件输出通过串行 `logQueue`（qos: .utility）异步写入，顺序保真
5. 同时输出到 `print()` (stdout) 和 `os_log()`（subsystem: `com.audiorecordmac`）

## 注意事项

1. **沙盒编译启动前请确认已授权** — 首次启动需要点击系统弹窗授权麦克风和音频捕获权限
2. **日志异步写入** — 发生 crash 时最后几条日志可能未 flush 到磁盘，需结合 `log show` 获取
3. **清理旧日志会丢失启动首条日志** — `clearLogFiles()` 删除了日志文件后重建，第一个 `logger.info("应用程序启动完成")` 会丢失
4. **非沙盒编译后日志路径改变** — 切换编译方式后记得检查对应目录
5. **容器路径需完整权限** — 读取 `~/Library/Containers/` 下的日志可能需要终端有完全磁盘访问权限
