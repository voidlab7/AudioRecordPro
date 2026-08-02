import Foundation
import CryptoKit

/// .arlock 文件元数据（解密后）
struct ArlockMetadata: Codable {
    var title: String
    let durationSec: Double
    let sampleRate: Double
    let channels: Int
    let bitsPerSample: Int
    let audioCodec: String
    let createdAt: String
    let sourceType: String
    let sourceApp: String
    
    init(title: String, durationSec: Double, sampleRate: Double, channels: Int,
         bitsPerSample: Int, audioCodec: String, createdAt: String,
         sourceType: String, sourceApp: String = "") {
        self.title = title
        self.durationSec = durationSec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.audioCodec = audioCodec
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.sourceApp = sourceApp
    }
}

/// 音频文件加密/解密器
/// AES-256-GCM 加密，自定义 .arlock 容器格式
///
/// 文件格式:
/// [Header: 40 bytes]
///   0x00: magic "ARLK"      4 bytes
///   0x04: version            1 byte
///   0x05: flags              1 byte
///   0x06: reserved           2 bytes
///   0x08: key_id (UUID)      16 bytes
///   0x18: audio_nonce        12 bytes
///   0x24: metadata_len       4 bytes (big-endian)
/// [Metadata Block]
///   0x28: metadata_nonce     12 bytes
///   0x34: metadata_cipher    N bytes
///   0x34+N: metadata_tag     16 bytes (GCM auth tag)
/// [Audio Block]
///   (0x34+N+16): audio_cipher   M bytes
///   (0x34+N+16+M): audio_tag    16 bytes (GCM auth tag)
class AudioFileEncryptor {
    
    static let shared = AudioFileEncryptor()
    private let logger = Logger.shared
    
    private init() {}
    
    // MARK: - Encrypt
    
    /// 加密音频数据并写入 .arlock 文件
    func encryptAndWrite(audioData: Data, metadata: ArlockMetadata, recordingUUID: UUID, outputURL: URL) throws {
        logger.info("开始加密录音 [\(recordingUUID.uuidString.prefix(8))...], audio=\(audioData.count) bytes")
        
        // 1. 派生 file_key
        let deviceID = DeviceFingerprint.shared.deviceID()
        let uuidData = recordingUUID.uuidData()
        let fileKey = deriveFileKey(deviceID: deviceID, recordingUUID: uuidData)
        let symKey = SymmetricKey(data: fileKey)
        
        // 2. 生成 nonce（audio 和 metadata 各用独立的）
        let audioNonce = generateNonce()
        let metadataNonce = generateNonce()
        
        // 3. 序列化元数据 JSON
        let encoder = JSONEncoder()
        let metadataJSON = try encoder.encode(metadata)
        
        // 4. AES-GCM 加密元数据
        let metaNonceObj = try AES.GCM.Nonce(data: metadataNonce)
        let metaBox = try AES.GCM.seal(metadataJSON, using: symKey, nonce: metaNonceObj)
        // metaBox: nonce + ciphertext + tag (all accessible as Data)
        
        // 5. AES-GCM 加密音频数据
        let audioNonceObj = try AES.GCM.Nonce(data: audioNonce)
        let audioBox = try AES.GCM.seal(audioData, using: symKey, nonce: audioNonceObj)
        
        // 6. 组装文件 (写前先计算总大小)
        let metaPayloadSize = AudioCryptoConfig.nonceLength + metaBox.ciphertext.count + AudioCryptoConfig.tagLength
        
        var fileData = Data()
        fileData.reserveCapacity(40 + metaPayloadSize + audioBox.ciphertext.count + AudioCryptoConfig.tagLength)
        
        // Header
        fileData.append(AudioCryptoConfig.magic)                    // 0x00: "ARLK"
        fileData.append(AudioCryptoConfig.containerVersion)          // 0x04: version=1
        fileData.append(AudioCryptoConfig.Flags.hasMetadata)         // 0x05: flags
        fileData.append(contentsOf: [0x00, 0x00])                   // 0x06-0x07: reserved
        fileData.append(uuidData)                                    // 0x08-0x17: key_id (UUID 16 bytes)
        fileData.append(audioNonce)                                  // 0x18-0x23: audio_nonce (12 bytes)
        fileData.append(UInt32(metaPayloadSize).bigEndianData)       // 0x24-0x27: metadata_len
        
        // Metadata Block
        fileData.append(metadataNonce)                               // 0x28: metadata_nonce (12 bytes)
        fileData.append(metaBox.ciphertext)                          // metadata ciphertext
        fileData.append(metaBox.tag)                                 // metadata GCM tag (16 bytes)
        
        // Audio Block
        fileData.append(audioBox.ciphertext)                         // audio ciphertext
        fileData.append(audioBox.tag)                                // audio GCM tag (16 bytes)
        
        // 7. 写入 — 先写 .tmp，再原子重命名（防 crash 留半截文件）
        let tmpURL = outputURL.deletingPathExtension().appendingPathExtension(AudioCryptoConfig.tmpFileExtension)
        try fileData.write(to: tmpURL, options: .atomic)
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: outputURL)
        
        logger.info("加密完成: \(ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file))")
    }
    
    // MARK: - Decrypt (full)
    
    /// 解密 .arlock 文件，返回音频数据和元数据
    func decrypt(from url: URL) throws -> (audioData: Data, metadata: ArlockMetadata) {
        let fileData = try Data(contentsOf: url)
        try validateHeader(fileData, url: url)
        
        let (_, audioNonce, symKey) = try parseHeaderAndDeriveKey(fileData)
        
        // 解析 metadata
        var offset = AudioCryptoConfig.HeaderOffset.metadataStart
        let metaPayloadSize = Int(UInt32(bigEndianFrom: fileData, at: AudioCryptoConfig.HeaderOffset.metadataLen))
        
        let metaNonceData = fileData.subdata(in: offset..<(offset + AudioCryptoConfig.nonceLength))
        offset += AudioCryptoConfig.nonceLength
        
        let metaCipherLen = metaPayloadSize - AudioCryptoConfig.nonceLength - AudioCryptoConfig.tagLength
        let metaCiphertext = fileData.subdata(in: offset..<(offset + metaCipherLen))
        offset += metaCipherLen
        
        let metaTag = fileData.subdata(in: offset..<(offset + AudioCryptoConfig.tagLength))
        offset += AudioCryptoConfig.tagLength
        
        // 解密 metadata
        let metaNonce = try AES.GCM.Nonce(data: metaNonceData)
        let metaBox = try AES.GCM.SealedBox(nonce: metaNonce, ciphertext: metaCiphertext, tag: metaTag)
        let metadataJSON = try AES.GCM.open(metaBox, using: symKey)
        
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(ArlockMetadata.self, from: metadataJSON)
        
        // 解析 audio
        let audioTagEnd = fileData.count
        let audioCipherEnd = audioTagEnd - AudioCryptoConfig.tagLength
        let audioCiphertext = fileData.subdata(in: offset..<audioCipherEnd)
        let audioTag = fileData.subdata(in: audioCipherEnd..<audioTagEnd)
        
        let audioNonceObj = try AES.GCM.Nonce(data: audioNonce)
        let audioBox = try AES.GCM.SealedBox(nonce: audioNonceObj, ciphertext: audioCiphertext, tag: audioTag)
        let audioData = try AES.GCM.open(audioBox, using: symKey)
        
        logger.info("解密成功: \(url.lastPathComponent) (\(metadata.durationSec.formattedDuration))")
        return (audioData, metadata)
    }
    
    /// 仅解密元数据（文件列表展示用，不加载完整音频数据）
    func decryptMetadataOnly(from url: URL) throws -> ArlockMetadata {
        let fileData = try Data(contentsOf: url)
        try validateHeader(fileData, url: url)
        
        let (_, _, symKey) = try parseHeaderAndDeriveKey(fileData)
        
        var offset = AudioCryptoConfig.HeaderOffset.metadataStart
        let metaPayloadSize = Int(UInt32(bigEndianFrom: fileData, at: AudioCryptoConfig.HeaderOffset.metadataLen))
        
        let metaNonceData = fileData.subdata(in: offset..<(offset + AudioCryptoConfig.nonceLength))
        offset += AudioCryptoConfig.nonceLength
        
        let metaCipherLen = metaPayloadSize - AudioCryptoConfig.nonceLength - AudioCryptoConfig.tagLength
        let metaCiphertext = fileData.subdata(in: offset..<(offset + metaCipherLen))
        offset += metaCipherLen
        
        let metaTag = fileData.subdata(in: offset..<(offset + AudioCryptoConfig.tagLength))
        
        let metaNonce = try AES.GCM.Nonce(data: metaNonceData)
        let metaBox = try AES.GCM.SealedBox(nonce: metaNonce, ciphertext: metaCiphertext, tag: metaTag)
        let metadataJSON = try AES.GCM.open(metaBox, using: symKey)
        
        let decoder = JSONDecoder()
        return try decoder.decode(ArlockMetadata.self, from: metadataJSON)
    }

    // MARK: - Update Metadata (V2.1: 持久化重命名)

    /// 仅更新 .arlock 文件的元数据（保持 UUID 不变，重加密整个文件）
    /// - Parameters:
    ///   - url: .arlock 文件路径
    ///   - transform: 闭包用于修改解出的元数据
    /// - Throws: 解密/加密/IO 失败
    ///
    /// 实现说明：
    /// 1. 解密完整文件（拿到 audioData + oldMetadata + recordingUUID）
    /// 2. 应用 transform 修改元数据
    /// 3. 用原 UUID 重新加密
    /// 4. 原子替换原文件
    func updateMetadata(in url: URL, transform: (inout ArlockMetadata) -> Void) throws {
        let (audioData, oldMetadata) = try decrypt(from: url)
        var newMetadata = oldMetadata
        transform(&newMetadata)

        // 从 .arlock 文件名（去掉扩展名）取回 UUID
        let uuidString = url.deletingPathExtension().lastPathComponent
        guard let recordingUUID = UUID(uuidString: uuidString) else {
            throw CryptoError.invalidFormat("无法从文件名解析 UUID: \(url.lastPathComponent)")
        }

        logger.info("更新 .arlock 元数据: \(recordingUUID.uuidString.prefix(8))...")
        try encryptAndWrite(
            audioData: audioData,
            metadata: newMetadata,
            recordingUUID: recordingUUID,
            outputURL: url
        )
    }

    /// 便捷方法：仅更新 title
    func updateTitle(in url: URL, newTitle: String) throws {
        try updateMetadata(in: url) { meta in
            meta.title = newTitle
        }
    }

    // MARK: - Private: Key Derivation
    
    private func deriveFileKey(deviceID: Data, recordingUUID: Data) -> Data {
        let message = deviceID + recordingUUID
        let key = SymmetricKey(data: AudioCryptoConfig.masterKey)
        let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(signature)
    }
    
    private func generateNonce() -> Data {
        var nonce = Data(count: AudioCryptoConfig.nonceLength)
        _ = nonce.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, AudioCryptoConfig.nonceLength, ptr.baseAddress!)
        }
        return nonce
    }
    
    // MARK: - Private: Parsing & Validation
    
    private func validateHeader(_ data: Data, url: URL) throws {
        guard data.count >= AudioCryptoConfig.HeaderOffset.metadataStart + 16 else {
            throw CryptoError.invalidFormat("文件太小：\(data.count) bytes")
        }
        
        let magic = data.subdata(in: 0..<4)
        guard magic == AudioCryptoConfig.magic else {
            // 检查前4字节以提供更好的错误信息
            let hex = magic.map { String(format: "%02X", $0) }.joined(separator: " ")
            throw CryptoError.invalidFormat("文件格式不正确 (期望 'ARLK'=41 52 4C 4B, 实际 \(hex))")
        }
        
        let version = data[AudioCryptoConfig.HeaderOffset.version]
        guard version <= AudioCryptoConfig.containerVersion else {
            throw CryptoError.unsupportedVersion("容器版本 \(version) 不受支持（当前 v\(AudioCryptoConfig.containerVersion)）")
        }
    }
    
    private func parseHeaderAndDeriveKey(_ data: Data) throws -> (UUID, Data, SymmetricKey) {
        // Extract key_id (UUID)
        let uuidBytes = data.subdata(
            in: AudioCryptoConfig.HeaderOffset.keyID..<(AudioCryptoConfig.HeaderOffset.keyID + AudioCryptoConfig.keyIDLength)
        )
        guard let recordingUUID = UUID(uuidData: uuidBytes) else {
            throw CryptoError.invalidFormat("无法解析录制 UUID")
        }
        
        // Extract audio nonce
        let audioNonce = data.subdata(
            in: AudioCryptoConfig.HeaderOffset.nonce..<(AudioCryptoConfig.HeaderOffset.nonce + AudioCryptoConfig.nonceLength)
        )
        
        // Derive key
        let deviceID = DeviceFingerprint.shared.deviceID()
        let keyData = deriveFileKey(deviceID: deviceID, recordingUUID: recordingUUID.uuidData())
        
        return (recordingUUID, audioNonce, SymmetricKey(data: keyData))
    }
}

// MARK: - CryptoError

enum CryptoError: Error, LocalizedError {
    case invalidFormat(String)
    case unsupportedVersion(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "文件格式错误: \(msg)"
        case .unsupportedVersion(let msg): return "版本不兼容: \(msg)"
        case .encryptionFailed(let msg): return "加密失败: \(msg)"
        case .decryptionFailed(let msg): return "解密失败: \(msg)"
        case .fileNotFound(let msg): return "文件不存在: \(msg)"
        }
    }
}

// MARK: - UUID Extensions

extension UUID {
    func uuidData() -> Data {
        let uuid = self.uuid
        return Data([
            uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ])
    }
    
    init?(uuidData: Data) {
        guard uuidData.count == 16 else { return nil }
        let bytes = uuidData.withUnsafeBytes { $0.load(as: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8).self) }
        self.init(uuid: (bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7, bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15))
    }
}

// MARK: - Helper Extensions

extension TimeInterval {
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension UInt32 {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

/// 从 Data 的指定偏移量读取 big-endian UInt32
private func UInt32(bigEndianFrom data: Data, at offset: Int) -> UInt32 {
    let range = offset..<(offset + 4)
    return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
}
