import Cocoa
import AudioToolbox

// MARK: - 转写文稿面板（FEAT-001 S2）
// 编辑器底部抽屉：展示 .atranscript.json 分段文稿 + 导出 MD + 手动转写

protocol TranscriptPanelDelegate: AnyObject {
    /// 点击「导出 MD」
    func transcriptPanelDidTapExport(_ panel: TranscriptPanelView)
    /// 点击「生成转写 / 重新转写」
    func transcriptPanelDidTapTranscribe(_ panel: TranscriptPanelView)
}

final class TranscriptPanelView: NSView {

    weak var delegate: TranscriptPanelDelegate?

    /// 转写语言偏好（UserDefaults key；"" = 跟随系统默认）
    static let localePrefKey = "transcription.localeID"
    /// 当前选中的转写 locale（nil = 自动/系统默认）
    static var preferredLocaleID: String? {
        let raw = UserDefaults.standard.string(forKey: localePrefKey) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private let titleLabel = NSTextField(labelWithString: "转写文稿".localized)
    private let metaLabel = NSTextField(labelWithString: "")
    private let localePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let exportButton = NSButton(title: "导出 MD".localized, target: nil, action: nil)
    private let transcribeButton = NSButton(title: "生成转写".localized, target: nil, action: nil)
    private let emptyLabel = NSTextField(wrappingLabelWithString: "暂无转写文稿\n点击右上角「生成转写」，音频将在本机完成转写（约 20 倍速）".localized)
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var hasTranscript = false
    /// 当前展示的文稿（状态恢复用）
    private var currentTranscript: Transcript?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor

        // 语言选择（FEAT-001 S2.5：英文演讲等非系统语言场景）
        localePopup.addItems(withTitles: ["语言: 自动".localized, "English", "中文"])
        localePopup.controlSize = .small
        localePopup.font = NSFont.systemFont(ofSize: 11)
        localePopup.translatesAutoresizingMaskIntoConstraints = false
        let saved = UserDefaults.standard.string(forKey: Self.localePrefKey) ?? ""
        localePopup.selectItem(at: saved == "en-US" ? 1 : (saved == "zh-CN" ? 2 : 0))
        localePopup.target = self
        localePopup.action = #selector(localeChanged)
        addSubview(localePopup)

        // 头部行
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = IndustrialColors.onSurface
        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = IndustrialColors.onSurfaceVariant

        for button in [exportButton, transcribeButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        exportButton.target = self
        exportButton.action = #selector(exportTapped)
        transcribeButton.target = self
        transcribeButton.action = #selector(transcribeTapped)

        // 正文（只读文稿）
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = IndustrialColors.onSurface
        scrollView.documentView = textView

        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = IndustrialColors.onSurfaceVariant
        emptyLabel.alignment = .center

        for v in [titleLabel, metaLabel, scrollView, emptyLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            metaLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),

            localePopup.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            localePopup.leadingAnchor.constraint(equalTo: metaLabel.trailingAnchor, constant: 12),
            localePopup.widthAnchor.constraint(equalToConstant: 110),

            transcribeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            transcribeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: transcribeButton.leadingAnchor, constant: -8),
            exportButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
        setEmptyState()
    }

    // MARK: - 状态

    /// 展示文稿（分段 + 时间戳）
    func show(transcript: Transcript) {
        hasTranscript = true
        currentTranscript = transcript
        emptyLabel.isHidden = true
        scrollView.isHidden = false
        exportButton.isEnabled = true
        transcribeButton.title = "重新转写".localized

        let text = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        for segment in transcript.segments where !segment.text.isEmpty {
            let stamp = NSAttributedString(
                string: String(format: "[%02d:%02d · %d 字]", Int(segment.start) / 60, Int(segment.start) % 60, segment.text.count),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                             .foregroundColor: IndustrialColors.onSurfaceVariant]
            )
            let body = NSAttributedString(
                string: segment.text + "\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: para,
                             .foregroundColor: IndustrialColors.onSurface]
            )
            text.append(stamp)
            text.append(body)
        }
        textView.textStorage?.setAttributedString(text)
        metaLabel.stringValue = "%d 字 · %@ · %@".localized(transcript.fullText.count, transcript.locale, transcript.engine)
    }

    /// 空状态（无文稿，可手动生成）
    func setEmptyState() {
        hasTranscript = false
        currentTranscript = nil
        scrollView.isHidden = true
        emptyLabel.isHidden = false
        exportButton.isEnabled = false
        transcribeButton.title = "生成转写".localized
        metaLabel.stringValue = ""
        textView.string = ""
    }

    /// 转写进行中（按钮置灰）
    func setTranscribing(_ busy: Bool) {
        transcribeButton.isEnabled = !busy
        exportButton.isEnabled = !busy && hasTranscript
        transcribeButton.title = busy ? "转写中…".localized : (hasTranscript ? "重新转写".localized : "生成转写".localized)
    }

    /// FEAT-001 S2.5: 临时状态（导出成功/失败等）——直接显示在面板元信息行（嵌入模式 statusBar 隐藏，此处必可见）
    func showStatus(_ text: String) {
        metaLabel.textColor = IndustrialColors.primary
        metaLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            self.metaLabel.textColor = IndustrialColors.onSurfaceVariant
            if let transcript = self.currentTranscript {
                self.metaLabel.stringValue = "%d 字 · %@ · %@".localized(transcript.fullText.count, transcript.locale, transcript.engine)
            }
        }
    }

    @objc private func exportTapped() { delegate?.transcriptPanelDidTapExport(self) }
    @objc private func transcribeTapped() { delegate?.transcriptPanelDidTapTranscribe(self) }

    /// 切换转写语言：持久化 + 通知（实时出字引擎下次会话生效）
    @objc private func localeChanged() {
        let localeID: String
        switch localePopup.indexOfSelectedItem {
        case 1: localeID = "en-US"
        case 2: localeID = "zh-CN"
        default: localeID = ""
        }
        UserDefaults.standard.set(localeID, forKey: Self.localePrefKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .init(Self.localePrefKey), object: nil)
        metaLabel.stringValue = localeID.isEmpty ? metaLabel.stringValue : "下次转写: %@".localized(localeID)
    }

    // MARK: - 导出

    /// Transcript → Markdown 文本（S2 导出格式）
    static func markdown(for transcript: Transcript, fileName: String) -> String {
        var md = "# \(fileName)\n\n"
        md += "> 转写引擎：\(transcript.engine) ｜ 语言：\(transcript.locale) ｜ 生成于 \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
        md += "## 全文\n\n\(transcript.fullText)\n"
        if transcript.segments.count > 1 {
            md += "\n## 分段\n\n"
            for segment in transcript.segments where !segment.text.isEmpty {
                let m = Int(segment.start) / 60, s = Int(segment.start) % 60
                md += "- **\(String(format: "%02d:%02d", m, s))** \(segment.text)\n"
            }
        }
        md += "\n---\n*由 Loocap 本机转写生成*\n"
        return md
    }

    /// FEAT-002: Transcript → 纯文本（txt 导出格式，无 Markdown 语法标记）
    static func plainText(for transcript: Transcript, fileName: String) -> String {
        var txt = "\(fileName)\n"
        txt += "转写引擎：\(transcript.engine) ｜ 语言：\(transcript.locale) ｜ 生成于 \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
        txt += String(repeating: "─", count: 24) + "\n\n"
        txt += "【全文】\n\(transcript.fullText)\n"
        if transcript.segments.count > 1 {
            txt += "\n【分段】\n"
            for segment in transcript.segments where !segment.text.isEmpty {
                let m = Int(segment.start) / 60, s = Int(segment.start) % 60
                txt += "[\(String(format: "%02d:%02d", m, s))] \(segment.text)\n"
            }
        }
        txt += "\n── 由 Loocap 本机转写生成 ──\n"
        return txt
    }
}
