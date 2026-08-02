import Foundation

/// 录音文件加密配置
/// 固定主密钥 + 设备指纹派生方案（方案 B-）
struct AudioCryptoConfig {
    
    // MARK: - 主密钥（编译时硬编码，32 bytes 随机数）
    /// ⚠️ 安全定位：此为"版权保护"层，非"DRM"层
    /// 硬编码方案无法防御反编译提取，但足以防御普通用户随意拷贝分发
    /// 产品文案不可宣称"军工级加密""不可破解"
    static let masterKey: Data = {
        // 32-byte random key generated at build time
        // In production, consider obfuscation or fetching from server
        let bytes: [UInt8] = [
            0x7A, 0xE3, 0x9F, 0x14, 0xC8, 0x2D, 0xB6, 0x51,
            0x93, 0x0F, 0x4A, 0x7D, 0xE2, 0x55, 0x18, 0x6C,
            0x3B, 0xA1, 0x9E, 0x47, 0xD0, 0x82, 0x66, 0xFA,
            0x5C, 0x31, 0x8B, 0x7F, 0xAD, 0x40, 0xCE, 0x29
        ]
        return Data(bytes)
    }()
    
    // MARK: - 容器格式常量
    
    /// .arlock 文件魔数
    static let magicBytes: [UInt8] = [0x41, 0x52, 0x4C, 0x4B] // "ARLK"
    static let magic: Data = Data(magicBytes)
    
    /// 容器版本号
    static let containerVersion: UInt8 = 1
    
    /// 预留字段值
    static let reserved: UInt16 = 0x0000
    
    /// 文件扩展名
    static let fileExtension = "arlock"
    
    /// 临时文件后缀（录制中，完成前）
    static let tmpFileExtension = "arlock.tmp"
    
    // MARK: - 文件头偏移量
    
    /// 各字段在 .arlock 文件中的偏移（字节）
    /// 文件格式:
    ///   [Header: 40 bytes]
    ///     0x00: magic "ARLK"      4 bytes
    ///     0x04: version            1 byte
    ///     0x05: flags              1 byte
    ///     0x06: reserved           2 bytes
    ///     0x08: key_id (UUID)      16 bytes
    ///     0x18: audio_nonce        12 bytes
    ///     0x24: metadata_len       4 bytes (big-endian)
    ///   [Metadata Block: starts at 0x28]
    ///     0x28: metadata_nonce     12 bytes
    ///     0x34: metadata_cipher    N bytes (GCM encrypted JSON)
    ///     0x34+N: metadata_tag     16 bytes (GCM auth tag)
    ///   [Audio Block]
    ///     (0x34+N+16): audio_cipher   M bytes (GCM encrypted AAC)
    ///     (0x34+N+16+M): audio_tag    16 bytes (GCM auth tag)
    struct HeaderOffset {
        static let magic = 0           // 0x00 - 0x03: "ARLK"
        static let version = 4         // 0x04: 容器版本
        static let flags = 5           // 0x05: 标志位
        static let reserved = 6        // 0x06 - 0x07: 预留
        static let keyID = 8           // 0x08 - 0x17: 录制 UUID（16 bytes）
        static let nonce = 24          // 0x18 - 0x23: 音频 AES-GCM IV（12 bytes）
        static let metadataLen = 36    // 0x24 - 0x27: metadata payload 长度（4 bytes, big-endian）
        // metadata block starts at 0x28 (40): nonce(12) + cipher(N) + tag(16)
        static let metadataStart = 40
    }
    
    // MARK: - 标志位
    
    struct Flags {
        static let hasMetadata: UInt8 = 0x01  // bit0
        // bit1-7: 保留
        static let reserved: UInt8 = 0x00
    }
    
    // MARK: - 临时文件
    
    struct TempFilePattern {
        /// 录制临时文件前缀
        static let recordingPrefix = ".rec_"
        /// 播放临时文件前缀
        static let playbackPrefix = ".playback_"
        /// 导出临时文件前缀
        static let exportPrefix = ".export_"
        /// 临时文件扩展名
        static let cafExtension = "caf"
        static let m4aExtension = "m4a"
    }
    
    // MARK: - 加密参数
    
    /// AES-GCM nonce 长度（12 bytes）
    static let nonceLength = 12
    /// AES-GCM tag 长度（16 bytes）
    static let tagLength = 16
    /// 密钥长度（32 bytes = AES-256）
    static let keyLength = 32
    /// key_id 长度（UUID = 16 bytes）
    static let keyIDLength = 16
    
    // MARK: - 元数据 JSON Schema
    
    struct MetadataKeys {
        static let title = "title"
        static let durationSec = "duration_sec"
        static let sampleRate = "sample_rate"
        static let channels = "channels"
        static let bitsPerSample = "bits_per_sample"
        static let audioCodec = "audio_codec"
        static let createdAt = "created_at"
        static let sourceType = "source_type"
        static let sourceApp = "source_app"
    }
}

// MARK: - 音频导出格式枚举
/// 导出格式（供 ExportService 使用）
public enum AudioExportFormat: String, CaseIterable, Sendable {
    case m4a = "m4a"
    case wav = "wav"
    case mp3 = "mp3"
    case flac = "flac"
    case aiff = "aiff"
    case ogg = "ogg"
    
    public var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV (PCM)"
        case .mp3: return "MP3"
        case .flac: return "FLAC"
        case .aiff: return "AIFF"
        case .ogg: return "OGG"
        }
    }
    
    public var fileExtension: String { rawValue }
    
    public var utTypeIdentifier: String {
        switch self {
        case .m4a: return "com.apple.m4a-audio"
        case .wav: return "com.microsoft.waveform-audio"
        case .mp3: return "public.mp3"
        case .flac: return "org.xiph.flac"
        case .aiff: return "public.aiff-audio"
        case .ogg: return "org.xiph.ogg-audio"
        }
    }
}
