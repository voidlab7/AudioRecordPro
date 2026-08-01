# REQ-2.0-07 录音文件版权保护（沙盒容器 + AES 加密自定义格式）

## 版本：V2.0 | 优先级：P0 | 状态：⬜ 待开发

## 背景

当前录音文件以标准 `M4A` / `WAV` 格式直接存储在 `~/Documents/AudioRecordings/` 目录（用户可在 Finder 中随意访问、复制、用任意播放器播放）。这带来两个问题：

1. **侵权风险**：用户录制系统声音（YouTube、网课、播客等）后，文件可被随意拷贝分发，App 无法对此负责，存在被 App Store 审核以"鼓励侵权"为由拒审的风险。
2. **商业价值流失**：付费功能（编辑、格式转换）失去壁垒——用户拷出 `.m4a` 后可在他处完成同样工作。

本需求通过 **"沙盒容器目录存储 + AES-256-GCM 加密 + 自定义 `.arlock` 文件格式 + App 内闭环播放 + 导出时才解封转码"** 四层防护，将录音文件锁定在 App 内部，外部无法直接播放。

> **设计决策（2026-07-25）**：
> - 不使用 Keychain 存储密钥（用户担忧授权体验）。改用**方案 B-：固定主密钥 + 设备指纹派生**，零用户交互。
> - 录制工作格式与存储格式分离：录制用 PCM/CAF（无损、临时、录完即删），存储用加密 `.arlock`。
> - 文件加密仅作为"版权保护"层，不作为"DRM"。产品文案不可宣称"军工级加密""不可破解"。

---

## 关联文件

| 文件 | 说明 |
|------|------|
| `AudioRecordKit/Sources/Utils/FileManagerUtils.swift` | 录音目录改为沙盒容器；删除自定义路径逻辑 |
| `AudioRecordKit/Sources/Utils/AudioFileEncryptor.swift` | **新增**：AES-256-GCM 加解密 + `.arlock` 容器读写 |
| `AudioRecordKit/Sources/Utils/DeviceFingerprint.swift` | **新增**：设备指纹（IOPlatformUUID 派生） |
| `AudioRecordKit/Sources/Utils/AudioCryptoConfig.swift` | **新增**：主密钥常量、文件头格式、版本号 |
| `AudioRecordApp/Sources/Controllers/AudioRecorderController.swift` | 录制完成回调改为：录完 → 加密 → 写 `.arlock` → 安全删除临时 PCM |
| `AudioRecordApp/Sources/Controllers/MainViewController.swift` | crash 恢复扫描临时目录；播放链路改为读 `.arlock` 解密 |
| `AudioRecordApp/Sources/Views/RecordedFilesView.swift` | 文件列表读 `.arlock`，元数据从文件头解析 |
| `AudioRecordApp/Sources/Views/SettingsWindowController.swift` | **删除**"自定义存储位置"设置项 |
| `AudioRecordApp/Sources/Services/ExportService.swift` | **新增**：导出 = 解密 + 转码 + NSSavePanel |
| `AudioRecordMac.entitlements` | 维持现状（`app-sandbox=true` 已配，无需新增 entitlement） |

---

## 1. 沙盒容器存储

### 1.1 目录改造

**当前实现**（`FileManagerUtils.swift:18-23`）：

```swift
func getRecordingsDirectory() -> URL {
    // 优先使用用户自定义目录
    if let customPath = UserDefaults.standard.string(forKey: "recordingsDirectory"),
       !customPath.isEmpty {
        ...
    }
    // 默认: ~/Documents/AudioRecordings/   ❌ 沙盒下不可写
}
```

**改造后**：

```swift
func getRecordingsDirectory() -> URL {
    // 沙盒容器目录（用户不可见、其他 App 不可访问）
    let containerURL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = containerURL.appendingPathComponent("Recordings", isDirectory: true)
    createDirectoryIfNeeded(at: dir)
    return dir
}
```

实际路径（沙盒下）：

```
~/Library/Containers/<bundle.id>/Data/Library/Application Support/Recordings/
```

### 1.2 删除自定义存储位置

| 改动点 | 说明 |
|--------|------|
| `SettingsWindowController.swift:158-191` | 删除"存储位置"区块 UI、目录选择按钮、UserDefaults 写入逻辑 |
| `FileManagerUtils.getRecordingsDirectory()` | 删除 `recordingsDirectory` UserDefaults 读取分支 |
| `v1-feature-breakdown.md` 第 198 行 | 录制设置移除"存储位置"项（保留格式/采样率） |

### 1.3 临时文件位置

录制过程中的 PCM/CAF 临时文件改写到 `NSTemporaryDirectory()`：

```
~/Library/Containers/<bundle.id>/Data/tmp/.rec_<uuid>.caf
```

**理由**：
- 临时目录不会被 Time Machine 备份（容器 tmp 不在备份范围）
- crash 恢复时只扫这个目录
- 录制完成后立即 secure-delete（覆盖 + 删除）

---

## 2. 录制格式：工作格式 vs 存储格式

### 2.1 录制工作格式（临时）

| 参数 | 值 | 理由 |
|------|-----|------|
| 容器 | CAF（Core Audio Format） | Apple 原生、AVAudioFile 原生支持、可流式写 |
| 编码 | PCM 16-bit（默认）/ 24-bit（Hi-Fi 选项） | 无损，避免二次压缩失真 |
| 采样率 | 48kHz | 与系统音频对齐 |
| 声道 | 立体声 / 单声道（按音源） | — |
| 文件大小（4h 立体声 16-bit） | ~2.6 GB | 仅作临时文件，录完即删 |

### 2.2 存储格式（持久化）

**自定义加密容器 `.arlock`**（AudioRecord Locked）：

```
偏移      字段                  长度      说明
─────────────────────────────────────────────────────────────
0x00      magic                 4 bytes   "ARLK"（固定，文件识别）
0x04      version               1 byte    = 1（容器版本号，未来升级用）
0x05      flags                 1 byte    bit0: 是否含 metadata；bit1-7: 保留
0x06      reserved              2 bytes   0x0000，对齐用
0x08      key_id                16 bytes  录制 UUID（用于派生 file_key）
0x18      nonce                 12 bytes  AES-GCM IV（每文件随机）
0x24      metadata_len          4 bytes   元数据明文长度（big-endian uint32）
0x28      metadata_ciphertext   N bytes   AES-GCM 加密的元数据 JSON
0x28+N    audio_ciphertext      M bytes   AES-GCM 加密的 AAC 音频数据
0x28+N+M  tag                   16 bytes  GCM 认证标签
─────────────────────────────────────────────────────────────
```

**元数据 JSON（加密前）**：

```json
{
  "title": "全部系统声音_2026-07-25_143020",
  "duration_sec": 1234.56,
  "sample_rate": 48000,
  "channels": 2,
  "bits_per_sample": 16,
  "audio_codec": "aac",        // 加密前的原始编码
  "created_at": "2026-07-25T14:30:20Z",
  "source_type": "system|process|mic|mixed",
  "source_app": "Google Chrome" // 进程录制时填，否则空
}
```

### 2.3 为什么不直接录 PCM 加密、不做 AAC 转码？

| 方案 | 文件大小（4h） | 优点 | 缺点 |
|------|---------------|------|------|
| PCM 直接加密 | ~2.6 GB | 无损、零延迟 | 文件巨大、容器目录膨胀 |
| AAC + 加密（**采用**） | ~230 MB | 文件小、与现 M4A 一致 | 录制完成需 ~30s 转码 |

**采用方案**：录制用 CAF/PCM 临时文件 → 录制完成后转码 AAC（128kbps，与现 V1.0 默认一致）→ AES-256-GCM 加密 → 写 `.arlock` → 删除临时 CAF。

AAC 转码不会带来音质可感知损失（128kbps AAC 是 V1.0 的标准格式，用户已接受）。

---

## 3. 密钥管理（方案 B-：设备指纹派生）

### 3.1 密钥派生流程

```
[编译时]  master_key (32 bytes 随机数，硬编码在 AudioCryptoConfig.swift)

[运行时-录制]  
  recording_uuid = UUID().bytes  (16 bytes)
  device_id      = SHA256(IOPlatformUUID)  (32 bytes)
  file_key       = HMAC-SHA256(master_key, device_id || recording_uuid)  (32 bytes)
  → 用 file_key 加密这条录音 → 写入 .arlock

[运行时-播放/导出]
  读 .arlock 头取 recording_uuid
  → 同公式算出 file_key
  → AES-GCM 解密
```

### 3.2 设备指纹获取

```swift
// DeviceFingerprint.swift
static func deviceID() -> Data {
    // IOPlatformUUID 不需要 entitlement，沙盒下可用
    let service = IOServiceGetMatchingService(
        kIOMasterPortDefault,
        IOServiceMatching("IOPlatformExpertDevice")
    )
    defer { IOObjectRelease(service) }
    guard let uuidCF = IORegistryEntryCreateCFProperty(
        service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
    )?.takeRetainedValue() as? String else {
        // 兜底：用 macOS host name + 当前用户名 hash
        return fallbackFingerprint()
    }
    return SHA256.hash(data: Data(uuidCF.utf8))
}
```

### 3.3 安全特性

| 特性 | 是否满足 | 说明 |
|------|---------|------|
| 用户零交互 | ✅ | 不弹 Keychain、不弹任何对话框 |
| 防"用其他播放器播放" | ✅ | 文件是 AES 密文，非标准音频格式 |
| 防"拷贝到其他 Mac 播放" | ✅ | `device_id` 变化 → `file_key` 变化 → 解密失败 |
| 防"同 Mac 卸载重装后失效" | ❌（特性而非缺陷） | `IOPlatformUUID` 不变，重装仍可解，符合用户预期 |
| 防"反编译 App 提取 master_key" | ❌ | 任何硬编码方案都无法防御，定位为"版权保护"而非"DRM" |
| 防"App 跨设备同步文件" | ✅ | iCloud Drive 同步的 `.arlock` 在新设备无法解密 |

### 3.4 与 Keychain 方案的对比

| 维度 | Keychain | 方案 B-（采用） |
|------|----------|----------------|
| 用户交互 | 沙盒下不弹窗（用户感知 0） | 0 |
| 设备绑定 | ✅ Keychain item 默认绑本机 | ✅ 通过 `device_id` 派生 |
| 卸载重装能否解密 | ❌ 默认不保留 | ✅ 可解 |
| 防 App 替换攻击 | ✅ | ❌（任何装了本 App 的同 Mac 都能解） |
| 实现复杂度 | 中 | 低（~50 行代码） |
| 用户主观接受度 | — | ✅ 用户明确要求不用 Keychain |

---

## 4. 录制流程时序

```
[RECORDING_START]
  1. 生成 recording_uuid (UUID)
  2. 创建临时文件: NSTemporaryDirectory()/.rec_<uuid>.caf
  3. AVAudioFile 写 PCM 16-bit 48kHz CAF
  4. 实时波形/电平/时长（从 AVAudioEngine tap 拿，不读文件）

[RECORDING_STOP]
  5. 关闭 AVAudioFile
  6. AVAssetExportSession 转码为 AAC 128kbps（内存中或临时 .m4a）
  7. 读 AAC 数据到 Data
  8. 派生 file_key = HMAC-SHA256(master_key, device_id || recording_uuid)
  9. 生成 nonce (12 bytes 随机)
  10. 构造 metadata JSON
  11. AES.GCM.seal(aac_data, using: file_key, nonce: nonce) → ciphertext + tag
  12. AES.GCM.seal(metadata_json, using: file_key, nonce: nonce2) → meta_ciphertext + meta_tag
  13. 组装 .arlock 文件头 + payload → 写入 Recordings/<uuid>.arlock
  14. secure-delete 临时 .caf 和 .m4a（覆写 0x00 后删除）
  15. 写入录制记录到 SQLite/UserDefaults（文件名、时长、uuid）
  16. 通知 UI 刷新文件列表

[CRASH 恢复]
  App 启动 → 扫描 NSTemporaryDirectory()/.rec_*.caf
  → 找到未完成的录音 → 弹窗"发现未保存的录音 X，是否恢复？"
  → 用户确认 → 走 STOP 步骤 5-15
  → 用户拒绝 → secure-delete 临时文件
```

### 4.1 性能预算

| 步骤 | 1h 录音 | 4h 录音 |
|------|---------|---------|
| AVAssetExportSession 转 AAC | ~8s | ~30s |
| AES-256-GCM 加密 | ~2s | ~8s |
| 写 `.arlock` | ~0.5s | ~2s |
| secure-delete 临时文件 | ~1s | ~5s |
| **总计停止后等待** | **~12s** | **~45s** |

> UX 处理：停止录制后立即显示"正在保存..."进度条，完成后跳转文件列表。

---

## 5. 播放链路

### 5.1 App 内播放

```
用户点击文件
  → 读 .arlock 头取 recording_uuid
  → 派生 file_key
  → AES.GCM.open(audio_ciphertext, using: file_key, nonce: nonce, tag: tag)
  → 得到 AAC Data
  → 写临时文件到 NSTemporaryDirectory()/.playback_<uuid>.m4a
  → AVAudioPlayer 播放
  → 播放结束或切换文件时 secure-delete 临时 .m4a
```

### 5.2 边界情况

| 情况 | 处理 |
|------|------|
| 文件被外部篡改 | GCM tag 校验失败 → 弹窗"文件已损坏" |
| 同 Mac 跨用户拷贝 | `device_id` 不同 → 解密失败 → 弹窗"文件不属于本设备" |
| App 升级 master_key 变更 | version 字段升级 → 走迁移逻辑（V2 暂不实现，仅在版本号预留） |
| 临时 .m4a 残留 | App 启动时清理 `NSTemporaryDirectory()/.playback_*` |

---

## 6. 导出流程

### 6.1 导出 = 解密 + 转码 + NSSavePanel

```
用户点"导出"
  → 弹 NSSavePanel：选目标路径 + 目标格式（M4A/WAV/MP3/FLAC/AIFF/OGG）
  → 读 .arlock → 解密 → 临时 .m4a
  → AVAssetExportSession 转码为目标格式
  → 写入用户选定的路径
  → secure-delete 临时 .m4a
  → 记录导出审计日志：时间 / 文件 uuid / 目标路径 / 目标格式
```

### 6.2 导出审计日志（V2.0 MVP 可选，V2.1 必做）

```swift
// ExportAuditLog.swift
struct ExportRecord: Codable {
    let recordingUUID: UUID
    let exportedAt: Date
    let targetPath: String
    let targetFormat: AudioFormat
    let deviceID: String  // 哪台设备导出的
}
```

存储位置：`Application Support/ExportLogs.jsonl`（JSON Lines，append-only）。

### 6.3 导出限制（付费墙）

| 用户类型 | 限制 |
|----------|------|
| 免费版 | 每天 3 次（V1.3 付费策略已定义） |
| Pro | 无限 |
| 单条录音导出次数 | 不限制（用户买了 Pro 即拥有该录音的完整所有权） |

---

## 7. 安全分级与产品定位

### 7.1 本方案能防御的威胁

| 威胁 | 防御 |
|------|------|
| 普通用户在 Finder 找到 `.m4a` 拷走播放 | ✅ 沙盒容器目录不可见 |
| 普通用户找到 `.arlock` 改扩展名为 `.m4a` 播放 | ✅ 是密文，QuickTime 报损坏 |
| 普通用户拷贝 `.arlock` 到其他 Mac 用本 App 播放 | ✅ `device_id` 不同，解密失败 |
| 普通用户上传 `.arlock` 到网盘分享 | ✅ 接收方无本 App 或非同 Mac，无法解 |
| 普通用户用 Audacity 直接打开 `.arlock` | ✅ 无法识别格式 |

### 7.2 本方案不能防御的威胁（明确不做）

| 威胁 | 不做原因 |
|------|---------|
| 专业用户用 Audio Hijack 在系统声卡层录制 | 不在 App 控制范围，任何录音 App 都防不住 |
| 逆向工程师反编译 App 提取 `master_key` | 需要 obfuscation / 白盒加密 / 服务器下发密钥，成本远超收益 |
| 同 Mac 上用户拷贝 `.arlock` + 装 App 用同账号 | 设备指纹相同 → 可解，但此场景极少且不可分发 |
| 用户在 App 内播放时用另一个设备录屏录声音 | 任何 DRM 都防不住，超出方案范围 |

### 7.3 产品文案规范

**✅ 可以说**：
- "录音文件加密存储，防止被随意拷贝分发"
- "文件锁定在 App 内，仅可由本 App 解密播放"
- "导出时才生成可分享的标准音频文件"

**❌ 不能说**：
- "军工级加密" / "银行级加密"
- "不可破解" / "绝对安全"
- "DRM 保护"（DRM 有严格的法律定义，本方案达不到）

---

## 8. App Store 合规

### 8.1 加密声明

App Store Connect 提交时需勾选 **"uses standard encryption only"** 豁免：

- AES-256-GCM 使用 Apple `CryptoKit` 系统库（`CryptoKit.AES.GCM`）
- HMAC-SHA256 使用 `CryptoKit.HMAC`
- SHA256 使用 `CryptoKit.SHA256`

均属于"标准加密算法的合规使用"，符合美国 BIS 出口豁免条件，**无需提交 ERN（Encryption Registration Number）**。

### 8.2 录音权限免责声明

App 内"关于"或首次启动引导中加入：

> 本工具用于录制您拥有合法权限的内容。请遵守当地版权法，用户对所录制内容的使用与分发负全部责任。

### 8.3 沙盒合规

- `app-sandbox = true` ✅ 已配置
- 文件访问全部走容器目录或 NSSavePanel ✅
- 不需要新增任何 entitlement
- `AudioRecordMac.entitlements` 维持现状

---

## 9. 落地里程碑

### P0（必做，V2.0 必交付）

| # | 任务 | 工期 | 依赖 |
|---|------|------|------|
| 1 | `FileManagerUtils` 改沙盒容器目录 + 删除自定义路径 | 0.5 天 | 无 |
| 2 | `SettingsWindowController` 删除"存储位置"区块 | 0.5 天 | #1 |
| 3 | 新建 `AudioCryptoConfig` / `DeviceFingerprint` | 0.5 天 | 无 |
| 4 | 新建 `AudioFileEncryptor`：AES-GCM 加解密 + `.arlock` 读写 | 2 天 | #3 |
| 5 | `AudioRecorderController` 录制完成回调接入加密链路 | 1 天 | #1 #4 |
| 6 | 临时文件 secure-delete 工具 | 0.5 天 | 无 |
| 7 | crash 恢复扫描临时目录逻辑改造 | 0.5 天 | #1 |
| 8 | `RecordedFilesView` 读 `.arlock` 元数据展示 | 1 天 | #4 |
| 9 | App 内播放链路改造（解密 → 临时 .m4a → 播放 → 清理） | 1.5 天 | #4 |
| 10 | `ExportService` 实现（解密 + 转码 + NSSavePanel） | 2 天 | #4 |
| **小计** | | **10 天（2 周）** | |

### P1（推荐，V2.0 尽量做）

| # | 任务 | 工期 |
|---|------|------|
| 11 | 导出审计日志（JSONL append） | 0.5 天 |
| 12 | 元数据从文件列表编辑同步回 `.arlock` | 1 天 |
| 13 | 长录音（>1h）保存进度 UI（进度条 + 取消按钮） | 1 天 |

### P2（增强，V2.1+）

| # | 任务 | 工期 |
|---|------|------|
| 14 | 音频水印（用户邮箱哈希嵌入 PCM，听不见） | 3-5 天 |
| 15 | 容器版本迁移工具（V1 → V2 升级） | 2 天 |
| 16 | 批量加密迁移工具（现有 `.m4a` 转 `.arlock`） | 1 天 |

---

## 10. 验收标准

| # | 标准 | 通过条件 |
|---|------|----------|
| 1 | 沙盒容器存储 | 录音文件不在 `~/Documents/` 出现，出现在 `~/Library/Containers/<bundle.id>/.../Recordings/` |
| 2 | 文件格式 | 录音目录下只有 `.arlock` 文件，无 `.m4a`/`.wav`/`.caf` |
| 3 | 临时文件清理 | 录制完成后 `NSTemporaryDirectory()` 无 `.rec_*` 残留 |
| 4 | 加密有效性 | 用 hex 编辑器打开 `.arlock`，前 4 字节为 `41 52 4C 4B`（"ARLK"），后续为不可读密文 |
| 5 | App 内播放 | 任意 `.arlock` 文件可在 App 内播放，音质清晰 |
| 6 | 跨设备解密失败 | `.arlock` 拷贝到另一台 Mac，App 内播放报"文件不属于本设备" |
| 7 | 篡改检测 | 篡改 `.arlock` 任意字节，App 内播放报"文件已损坏" |
| 8 | 导出格式 | 导出 M4A/WAV/MP3 可在 QuickTime / VLC 正常播放 |
| 9 | 导出后清理 | 导出完成后 `NSTemporaryDirectory()` 无 `.playback_*` 残留 |
| 10 | 设置页 | "存储位置"项已删除，无自定义路径入口 |
| 11 | crash 恢复 | 录制中强杀 App → 重启 → 弹窗恢复 → 文件可正常播放 |
| 12 | 长时录制 | 4 小时录制停止后保存 < 60s，无崩溃 |
| 13 | App Store 审核 | 沙盒 + 加密声明勾选后审核通过 |

### 负向测试

| # | 场景 | 预期 |
|---|------|------|
| 14 | 删除 `.arlock` 中间字节 | 解密失败，弹窗"文件已损坏"，不崩溃 |
| 15 | 手动构造非法 magic 的文件 | 列表过滤掉，不显示 |
| 16 | 同名 `.arlock` 冲突 | UUID 不同不会冲突，文件名用 UUID |
| 17 | 磁盘满 | 加密写文件失败 → secure-delete 临时 PCM → 弹窗"保存失败，已保留临时录音" |
| 18 | 跨用户拷贝（同 Mac 切换用户） | `device_id` 不同 → 解密失败 |

---

## 11. NOT in scope

| 不做 | 原因 |
|------|------|
| 服务器端密钥分发 | 独立开发者无服务器成本预算；V1 定位纯本地 |
| 白盒加密 / 代码混淆 | 成本极高，收益有限（防的是逆向工程师，不是目标用户） |
| 完整 DRM（数字版权管理） | 法律定义严格，本方案达不到；定位为"版权保护" |
| 音频水印（V2.0） | 实现复杂，留到 V2.1+，导出审计日志已够溯源 |
| iCloud 同步 `.arlock` | 设备绑定导致跨设备无法解，反而引发用户困惑 |
| 容器版本迁移工具（V2.0） | V1 容器格式尚未发布，无遗留数据需迁移 |
| 多设备共享密钥（家庭共享） | 与"设备绑定"目标冲突，用户场景不明确 |

---

## 12. 风险评估

| # | 风险 | 概率 | 影响 | 风险值 | 缓解措施 |
|---|------|------|------|--------|----------|
| 1 | **App Store 审核以"鼓励侵权"为由拒审** | 中 | 高 | ⭐⭐⭐⭐ | 录音权限免责声明 + 文件加密存储证明"非主动协助分发" |
| 2 | **`master_key` 被反编译提取** | 中 | 低 | ⭐⭐ | 定位为"版权保护"非"DRM"；接受风险；产品文案不夸大 |
| 3 | **`IOPlatformUUID` 在某些 Mac 上返回空** | 低 | 中 | ⭐⭐ | 兜底用 `Host.current().localizedName` + `NSUserName()` 哈希 |
| 4 | **4h 录音加密耗时超 60s 用户感知差** | 中 | 中 | ⭐⭐⭐ | 进度条 UI + 后台异步加密 + 临时 PCM 保留直到加密完成 |
| 5 | **crash 恢复扫描到部分写入的 `.arlock`** | 中 | 中 | ⭐⭐⭐ | 加密过程中先写 `.arlock.tmp`，完成后原子重命名 |
| 6 | **临时 `.caf`/`.m4a` 被数据恢复工具恢复** | 低 | 中 | ⭐⭐ | secure-delete 覆写 3 次（0x00 / 0xFF / 0x00）；SSD 下 TRIM 自动擦除 |
| 7 | **同 Mac 跨用户拷贝文件后装 App 解密成功** | 低 | 低 | ⭐ | `device_id` 含用户名哈希兜底，跨用户失败；接受同用户跨 App 实例的弱保护 |
| 8 | **V1 老用户已有 `~/Documents/AudioRecordings/*.m4a`** | 高 | 中 | ⭐⭐⭐⭐ | 首次启动弹窗"检测到旧版录音，是否迁移到加密存储？"→ 批量转 `.arlock` |

---

## 13. 与现有文档的关系

| 现有文档 | 冲突点 | 处理 |
|----------|--------|------|
| `docs/产品/v1-feature-breakdown.md` §4 文件管理 | 存储位置 `~/Documents/AudioRecordings/` | 标记为 V1.0 旧设计，本 REQ 取代 |
| `docs/产品/v1-feature-breakdown.md` §7 设置页面 | "存储位置"设置项 | 删除该项 |
| `docs/产品/v1-feature-breakdown.md` §3 基础导出 | "可另存为到指定位置" | 保留，由 `ExportService` 实现，但文件不再是明文 |
| `AudioRecordKit/Sources/Utils/FileManagerUtils.swift` | `getRecordingsDirectory()` 实现 | 按 §1.1 改造 |
| `AudioRecordApp/Sources/Views/SettingsWindowController.swift` | "存储位置"区块 | 按 §1.2 删除 |

---

## 14. 决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-07-25 | 不使用 Keychain 存密钥 | 用户担忧授权体验；沙盒下虽不弹窗，但用户主观不接受。改用设备指纹派生 |
| 2026-07-25 | 录制工作格式用 CAF/PCM，存储格式用 AAC + 加密 | PCM 直存体积过大（4h=2.6GB）；AAC 与 V1.0 默认音质一致，文件仅 ~230MB |
| 2026-07-25 | 文件名用 UUID，不用"模式_日期_时间" | UUID 防 Unicode 文件名问题 + 跨设备唯一 + 防止用户在容器目录直接看文件名猜内容 |
| 2026-07-25 | 元数据也加密 | 防止用户从 `.arlock` 头看到"Google Chrome_2026-07-25"等敏感元数据 |
| 2026-07-25 | 接受"同 Mac 同用户的另一实例 App 可解密" | 此场景极少（同一台 Mac 同一用户装两个相同 App），且不可分发，符合产品定位 |
| 2026-07-25 | 不做 iCloud 同步 `.arlock` | 设备绑定导致跨设备无法解，反而引发客诉 |
