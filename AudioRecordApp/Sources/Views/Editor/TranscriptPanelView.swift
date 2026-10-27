import Cocoa
import AudioToolbox

// MARK: - 转写文稿面板（FEAT-001 S2）
// 编辑器底部抽屉：展示 .atranscript.json 分段文稿 + 导出 txt/MD（FEAT-002 双格式）+ 手动转写

protocol TranscriptPanelDelegate: AnyObject {
    /// 点击「导出」（txt 默认 / md 可选，FEAT-002）
    func transcriptPanelDidTapExport(_ panel: TranscriptPanelView)
    /// 点击「生成转写 / 重新转写」
    func transcriptPanelDidTapTranscribe(_ panel: TranscriptPanelView)
    /// UI-019: 拖柄拖拽调高（height 为面板总高，Controller 负责夹取范围与应用约束）
    func transcriptPanel(_ panel: TranscriptPanelView, didDragToHeight height: CGFloat)
    /// UI-019: 双击拖柄 → 折叠/展开切换
    func transcriptPanelDidToggleFold(_ panel: TranscriptPanelView)
    /// UI-021: 点句跳转（播放头落句起点 + 波形区间高亮，B 稿 state=5）
    func transcriptPanel(_ panel: TranscriptPanelView, didTapSegment segmentIndex: Int, start: TimeInterval, end: TimeInterval)
    /// UI-021: 搜索命中跳转（与点句同联动）
    func transcriptPanel(_ panel: TranscriptPanelView, didSeekSearchHit start: TimeInterval, end: TimeInterval)
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
    /// UI-019: 顶部拖柄（高 5，把手 36×3 居中；拖拽调高 / 双击折叠）
    private let dragBar = TranscriptDragBarView()
    private let localePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let exportButton = NSButton(title: "导出".localized, target: nil, action: nil)
    private let transcribeButton = NSButton(title: "生成转写".localized, target: nil, action: nil)
    private let emptyLabel = NSTextField(wrappingLabelWithString: "暂无转写文稿\n点击右上角「生成转写」，音频将在本机完成转写（约 20 倍速）".localized)
    private let scrollView = NSScrollView()
    /// UI-021: 点击感知文稿视图（点句跳转）
    private let textView = TranscriptTextView()
    private var hasTranscript = false
    /// UI-019: 折叠态（34px 仅标题条；正文隐藏）
    private(set) var isFolded = false
    /// 当前展示的文稿（状态恢复用）
    private var currentTranscript: Transcript?

    // MARK: UI-021 转写联动状态
    /// 句映射：正文文本 range ↔ segment（渲染 show() 时填充）
    private struct SegmentMapping {
        let textRange: NSRange
        let segmentIndex: Int
        let start: TimeInterval
        let end: TimeInterval
    }
    private var segmentMappings: [SegmentMapping] = []
    /// 当前播放句（teal 底 + 自动滚动）
    private var activeSegmentIndex: Int?
    /// 搜索：命中句索引列表 + 当前命中游标
    private var searchHitIndexes: [Int] = []
    private var searchCursor: Int = -1
    private var searchQuery: String = ""

    // UI-021: 搜索条 + 进度环
    private let searchField = NSSearchField()
    private let prevHitButton = NSButton(title: "↑".localized, target: nil, action: nil)
    private let nextHitButton = NSButton(title: "↓".localized, target: nil, action: nil)
    private let hitCountLabel = NSTextField(labelWithString: "")
    private let transcribingRing = ProgressRingView()

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

        // UI-019: 顶部拖柄（设计稿 .dragbar：高 5、背景 surface、把手 36×3 圆角 2）
        dragBar.translatesAutoresizingMaskIntoConstraints = false
        dragBar.onDrag = { [weak self] heightInWindowDelta in
            guard let self, let delegate = self.delegate else { return }
            // 面板顶在窗口坐标系向上拖 → 增高：delta 为窗口 y 增量（向上为正）
            let current = self.frame.height
            delegate.transcriptPanel(self, didDragToHeight: current + heightInWindowDelta)
        }
        dragBar.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.delegate?.transcriptPanelDidToggleFold(self)
        }
        addSubview(dragBar)

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
        // UI-021: 点句跳转（映射内命中才回调，落空白忽略）
        textView.onCharacterTap = { [weak self] charIndex in
            guard let self,
                  let m = self.segmentMappings.first(where: { NSLocationInRange(charIndex, $0.textRange) }) else { return }
            self.delegate?.transcriptPanel(self, didTapSegment: m.segmentIndex, start: m.start, end: m.end)
        }
        scrollView.documentView = textView

        // UI-021: 搜索条（关键词句内黄高亮 + 上/下句跳转，B 稿 state=5）
        setupSearchBar()

        // UI-021: 转写进行中进度环（B 稿 .ring：紫 #B387FF 旋转，挂在标题行）
        transcribingRing.translatesAutoresizingMaskIntoConstraints = false
        transcribingRing.isHidden = true
        addSubview(transcribingRing)

        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = IndustrialColors.onSurfaceVariant
        emptyLabel.alignment = .center

        for v in [titleLabel, metaLabel, scrollView, emptyLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for v in [searchField, prevHitButton, nextHitButton, hitCountLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            // UI-019: 拖柄贴顶，头部行挂拖柄下方
            dragBar.topAnchor.constraint(equalTo: topAnchor),
            dragBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragBar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorTranscriptDragBarHeight),

            titleLabel.topAnchor.constraint(equalTo: dragBar.bottomAnchor, constant: 4),
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

            // UI-021: 进度环挂在标题左侧（转写进行中显示）
            transcribingRing.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            transcribingRing.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            transcribingRing.widthAnchor.constraint(equalToConstant: 18),
            transcribingRing.heightAnchor.constraint(equalToConstant: 18),

            // UI-021: 搜索条第二行
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.widthAnchor.constraint(equalToConstant: 220),
            searchField.heightAnchor.constraint(equalToConstant: 22),

            hitCountLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            hitCountLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            hitCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),

            nextHitButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            nextHitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            nextHitButton.widthAnchor.constraint(equalToConstant: 26),

            prevHitButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            prevHitButton.trailingAnchor.constraint(equalTo: nextHitButton.leadingAnchor, constant: -4),
            prevHitButton.widthAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
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

    // MARK: - UI-021 搜索条

    private func setupSearchBar() {
        searchField.placeholderString = "搜索文稿".localized
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: 11)
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        // Cmd+F 聚焦（窗口级快捷键走 textView 侧无法覆盖，这里用面板内搜索按钮触发即可）

        for button in [prevHitButton, nextHitButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.isEnabled = false
            if button === prevHitButton {
                button.target = self
                button.action = #selector(previousHitTapped)
            } else {
                button.target = self
                button.action = #selector(nextHitTapped)
            }
        }
        hitCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        hitCountLabel.textColor = IndustrialColors.onSurfaceVariant
    }

    @objc private func searchFieldChanged() {
        performSearch(searchField.stringValue)
    }

    @objc private func previousHitTapped() { stepSearchHit(-1) }
    @objc private func nextHitTapped() { stepSearchHit(1) }

    /// 关键词搜索：句级命中（命中句黄底 #FFD600@30%），更新计数与按钮态
    private func performSearch(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchHitIndexes = []
        searchCursor = -1

        if searchQuery.isEmpty {
            refreshHighlights()
            updateSearchUI()
            return
        }
        for m in segmentMappings {
            let segText = (textView.string as NSString)
            guard m.textRange.location + m.textRange.length <= segText.length else { continue }
            let body = segText.substring(with: m.textRange)
            if body.localizedCaseInsensitiveContains(searchQuery) {
                searchHitIndexes.append(m.segmentIndex)
            }
        }
        refreshHighlights()
        updateSearchUI()
        if !searchHitIndexes.isEmpty {
            stepSearchHit(1)
        }
    }

    /// 上/下句跳转（循环）
    private func stepSearchHit(_ delta: Int) {
        guard !searchHitIndexes.isEmpty else { return }
        searchCursor = (searchCursor + delta + searchHitIndexes.count) % searchHitIndexes.count
        let segIndex = searchHitIndexes[searchCursor]
        scrollToSegment(segIndex)
        refreshHighlights()
        updateSearchUI()
        // 搜索跳转同步联动波形（与点句同联动）
        if let m = segmentMappings.first(where: { $0.segmentIndex == segIndex }) {
            delegate?.transcriptPanel(self, didSeekSearchHit: m.start, end: m.end)
        }
    }

    private func updateSearchUI() {
        let hasHits = !searchHitIndexes.isEmpty
        prevHitButton.isEnabled = hasHits
        nextHitButton.isEnabled = hasHits
        hitCountLabel.stringValue = searchQuery.isEmpty ? "" : (hasHits ? "%d/%d".localized(searchCursor + 1, searchHitIndexes.count) : "无命中".localized)
    }

    // MARK: - UI-021 高亮

    /// 全量重绘句底色：base（无）→ 搜索命中黄底 → 当前播放句 teal 底（搜索优先级更高）
    private func refreshHighlights() {
        let text = textView.string as NSString
        textStorage: do {
            guard let storage = textView.textStorage else { break textStorage }
            // 清全部底色
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: text.length))
            // 搜索命中黄底（#FFD600 @30%）
            let searchBg = NSColor(red: 1.0, green: 0.839, blue: 0.0, alpha: 0.30)
            for idx in searchHitIndexes {
                if let m = segmentMappings.first(where: { $0.segmentIndex == idx }) {
                    storage.addAttribute(.backgroundColor, value: searchBg, range: m.textRange)
                }
            }
            // 当前播放句 teal 底（10%）——不覆盖搜索黄底
            if let active = activeSegmentIndex, !searchHitIndexes.contains(active),
               let m = segmentMappings.first(where: { $0.segmentIndex == active }) {
                storage.addAttribute(.backgroundColor, value: IndustrialColors.primary.withAlphaComponent(0.10), range: m.textRange)
            }
        }
    }

    /// 滚动使句可见（iOS scrollRangeToVisible 等价）
    private func scrollToSegment(_ segmentIndex: Int) {
        guard let m = segmentMappings.first(where: { $0.segmentIndex == segmentIndex }) else { return }
        textView.scrollRangeToVisible(m.textRange)
    }

    // MARK: - UI-021 联动查询/更新（Controller 播放 timer 驱动）

    /// 返回包含时间 t 的句映射（nil = 无转写或落句间空隙）
    func segmentContaining(_ t: TimeInterval) -> (segmentIndex: Int, start: TimeInterval, end: TimeInterval)? {
        guard let m = segmentMappings.first(where: { t >= $0.start && t < $0.end }) else { return nil }
        return (m.segmentIndex, m.start, m.end)
    }

    /// 更新当前播放句：变化时重绘底色 + 滚动进视野（nil = 清高亮）
    func updateActiveSegment(_ segmentIndex: Int?) {
        guard segmentIndex != activeSegmentIndex else { return }
        activeSegmentIndex = segmentIndex
        refreshHighlights()
        if let idx = segmentIndex {
            scrollToSegment(idx)
        }
    }

    // MARK: - 状态

    /// UI-019: 折叠/展开（折叠 = 34px 仅标题条，正文隐藏）
    func setFolded(_ folded: Bool) {
        isFolded = folded
        scrollView.isHidden = folded || !hasTranscript ? true : false
        emptyLabel.isHidden = folded || hasTranscript ? true : false
        localePopup.isHidden = folded
        exportButton.isHidden = folded
        transcribeButton.isHidden = folded
        // UI-021: 搜索条随正文显隐
        searchField.isHidden = folded || !hasTranscript
        prevHitButton.isHidden = folded || !hasTranscript
        nextHitButton.isHidden = folded || !hasTranscript
        hitCountLabel.isHidden = folded || !hasTranscript
    }

    /// 展示文稿（分段 + 时间戳；UI-021 同时建立句映射供点句跳转/高亮/搜索）
    func show(transcript: Transcript) {
        hasTranscript = true
        currentTranscript = transcript
        emptyLabel.isHidden = true
        scrollView.isHidden = false
        searchField.isHidden = false
        prevHitButton.isHidden = isFolded
        nextHitButton.isHidden = isFolded
        hitCountLabel.isHidden = isFolded
        exportButton.isEnabled = true
        transcribeButton.title = "重新转写".localized

        let text = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        segmentMappings = []
        activeSegmentIndex = nil
        searchHitIndexes = []
        searchCursor = -1
        for (idx, segment) in transcript.segments.enumerated() where !segment.text.isEmpty {
            let base = text.length
            let stamp = NSAttributedString(
                string: String(format: "[%02d:%02d · %d 字]".localized, Int(segment.start) / 60, Int(segment.start) % 60, segment.text.count),  // REL-003
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
            // UI-021: 句映射覆盖 stamp+正文整段（含换行前的全部字符；换行符排除避免跨句命中）
            segmentMappings.append(SegmentMapping(
                textRange: NSRange(location: base, length: stamp.length + segment.text.count),
                segmentIndex: idx,
                start: segment.start,
                end: segment.end
            ))
        }
        textView.textStorage?.setAttributedString(text)
        metaLabel.stringValue = "%d 字 · %@ · %@".localized(transcript.fullText.count, transcript.locale, transcript.engine)
        updateSearchUI()
    }

    /// 空状态（无文稿，可手动生成）
    func setEmptyState() {
        hasTranscript = false
        currentTranscript = nil
        scrollView.isHidden = true
        emptyLabel.isHidden = false
        searchField.isHidden = true
        prevHitButton.isHidden = true
        nextHitButton.isHidden = true
        hitCountLabel.isHidden = true
        exportButton.isEnabled = false
        transcribeButton.title = "生成转写".localized
        metaLabel.stringValue = ""
        textView.string = ""
        segmentMappings = []
        activeSegmentIndex = nil
        searchHitIndexes = []
        searchCursor = -1
        searchQuery = ""
        searchField.stringValue = ""
    }

    /// 转写进行中（按钮置灰 + 紫进度环，B 稿 state=6a .tprog）
    func setTranscribing(_ busy: Bool) {
        transcribeButton.isEnabled = !busy
        exportButton.isEnabled = !busy && hasTranscript
        transcribeButton.title = busy ? "转写中…".localized : (hasTranscript ? "重新转写".localized : "生成转写".localized)
        transcribingRing.isHidden = !busy
        if busy {
            transcribingRing.start()
        } else {
            transcribingRing.stop()
        }
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
        // REL-003: 导出产物为用户可见内容，结构文案走本地化
        md += "> " + "转写引擎：%@ ｜ 语言：%@ ｜ 生成于 %@".localized(transcript.engine, transcript.locale, transcript.createdAt.formatted(date: .abbreviated, time: .shortened)) + "\n\n"
        md += "## " + "全文".localized + "\n\n\(transcript.fullText)\n"
        if transcript.segments.count > 1 {
            md += "\n## " + "分段".localized + "\n\n"
            for segment in transcript.segments where !segment.text.isEmpty {
                let m = Int(segment.start) / 60, s = Int(segment.start) % 60
                md += "- **\(String(format: "%02d:%02d", m, s))** \(segment.text)\n"
            }
        }
        md += "\n---\n*" + "由 Loocap 本机转写生成".localized + "*\n"
        return md
    }

    /// FEAT-002: Transcript → 纯文本（txt 导出格式，无 Markdown 语法标记）
    static func plainText(for transcript: Transcript, fileName: String) -> String {
        var txt = "\(fileName)\n"
        txt += "转写引擎：%@ ｜ 语言：%@ ｜ 生成于 %@".localized(transcript.engine, transcript.locale, transcript.createdAt.formatted(date: .abbreviated, time: .shortened)) + "\n"
        txt += String(repeating: "─", count: 24) + "\n\n"
        txt += "【" + "全文".localized + "】\n\(transcript.fullText)\n"
        if transcript.segments.count > 1 {
            txt += "\n【" + "分段".localized + "】\n"
            for segment in transcript.segments where !segment.text.isEmpty {
                let m = Int(segment.start) / 60, s = Int(segment.start) % 60
                txt += "[\(String(format: "%02d:%02d", m, s))] \(segment.text)\n"
            }
        }
        txt += "\n── " + "由 Loocap 本机转写生成".localized + " ──\n"
        return txt
    }
}

// MARK: - TranscriptDragBarView（UI-019）
/// 转写分栏顶部拖柄：高 5 / 把手 36×3 / 拖拽调高 / 双击折叠
/// 设计稿 .dragbar：背景 surface，cursor row-resize
final class TranscriptDragBarView: NSView {

    /// 拖拽回调：参数为窗口坐标系 y 增量（向上拖为正 → 分栏增高）
    var onDrag: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var dragStartYInWindow: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surface.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 把手 36×3 圆角 2 居中
        let handle = NSRect(x: (bounds.width - 36) / 2, y: (bounds.height - 3) / 2, width: 36, height: 3)
        let path = NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2)
        IndustrialColors.surfaceContainerHigh.setFill()
        path.fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        dragStartYInWindow = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        let dy = event.locationInWindow.y - dragStartYInWindow
        dragStartYInWindow = event.locationInWindow.y
        onDrag?(dy)
    }
}

// MARK: - TranscriptTextView（UI-021）
/// 点击感知的只读文稿视图：mouseDown 换算字符 index 回调（点句跳转）
final class TranscriptTextView: NSTextView {

    /// 点击字符 index 回调（未命中任何句由调用方过滤）
    var onCharacterTap: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // 只读文稿：单击定位句，不进入选择态（双击保留原生选择）
        if event.clickCount == 1 {
            let point = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndex(for: point)
            onCharacterTap?(charIndex)
            return
        }
        super.mouseDown(with: event)
    }
}

// MARK: - ProgressRingView（UI-021）
/// 转写进行中进度环（B 稿 .ring：22px、2.5px 边、紫色 #B387FF 顶弧旋转）
final class ProgressRingView: NSView {

    private var displayLink: CVDisplayLink?
    private var rotation: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 4 else { return }
        let inset: CGFloat = 2.5
        let ringRect = bounds.insetBy(dx: inset, dy: inset)
        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = 2.5
        // 底环（hover 色）
        NSColor(white: 1.0, alpha: 0.12).setStroke()
        track.stroke()
        // 旋转顶弧（紫 #B387FF，120°）
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2
        let startAngle = rotation * 180 / .pi
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle + 120, clockwise: false)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        NSColor(red: 0.702, green: 0.529, blue: 1.0, alpha: 1.0).setStroke()
        arc.stroke()
    }

    func start() {
        guard displayLink == nil else { return }
        let link = UnsafeMutablePointer<CVDisplayLink?>.allocate(capacity: 1)
        CVDisplayLinkCreateWithActiveCGDisplays(link)
        displayLink = link.pointee
        link.deallocate()
        CVDisplayLinkSetOutputHandler(displayLink!) { [weak self] _, _, _, _, _ -> CVReturn in
            DispatchQueue.main.async {
                guard let self, !self.isHidden else { return }
                self.rotation += 0.09
                self.needsDisplay = true
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(displayLink!)
    }

    func stop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }
}
