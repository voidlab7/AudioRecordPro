import Cocoa

// MARK: - SelectionReadoutDelegate
protocol SelectionReadoutDelegate: AnyObject {
    /// 键入生效（Enter / 失焦提交）：起点/终点直接设置；时长输入 = 保持起点调终点
    func selectionReadout(_ readout: SelectionReadoutView, didCommitStart start: TimeInterval?, end: TimeInterval?)
}

// MARK: - SelectionReadoutView
/// UI-020: 选区读数三框（B 稿 .readout）— 起点 / 终点 / 时长，10.5 mono 可键入
/// Enter 生效；非法值（非数字 / 负数 / 超时长 / 终点≤起点）红框不生效
class SelectionReadoutView: NSView, NSTextFieldDelegate {

    // MARK: - 输入框（带标签）
    private final class ReadoutField: NSView {
        let field = NSTextField()
        let titleLabel = NSTextField(labelWithString: "")
        private var isValid = true

        init(title: String, placeholder: String) {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 4
            layer?.borderWidth = 1
            layer?.borderColor = IndustrialColors.borderMuted.cgColor

            titleLabel.stringValue = title
            titleLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            titleLabel.textColor = IndustrialColors.textTertiary
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)

            field.stringValue = placeholder
            field.font = IndustrialTypography.monoReadout
            field.textColor = IndustrialColors.textSecondary
            field.backgroundColor = .clear
            field.drawsBackground = false
            field.isBordered = false
            field.focusRingType = .none
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 22),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                field.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(greaterThanOrEqualToConstant: 108)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setInvalid(_ invalid: Bool) {
            isValid = !invalid
            layer?.borderColor = invalid
                ? IndustrialColors.editorReadoutInvalid.cgColor
                : IndustrialColors.borderMuted.cgColor
        }
    }

    // MARK: - UI
    private let startField = ReadoutField(title: "起点", placeholder: "00:00.000")
    private let endField = ReadoutField(title: "终点", placeholder: "00:00.000")
    private let durationField = ReadoutField(title: "时长", placeholder: "0.000s")

    /// 键入期间不回写显示（避免打断输入）
    private var isEditing = false
    /// 总时长上界（Controller 加载后设置）
    var totalDuration: TimeInterval = 0
    weak var delegate: SelectionReadoutDelegate?

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        let stack = NSStackView(views: [startField, endField, durationField])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for f in [startField, endField, durationField] {
            f.field.delegate = self
            // Enter 生效：NSTextField 默认在 doCommandBy selectLine 时提交，用 target/action + 自定义处理
            f.field.target = self
            f.field.action = #selector(fieldAction(_:))
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: - 显示回写（selection 变化时）

    func update(start: TimeInterval?, end: TimeInterval?) {
        guard !isEditing else { return }
        guard let s = start, let e = end else {
            startField.field.stringValue = "—"
            endField.field.stringValue = "—"
            durationField.field.stringValue = "—"
            startField.setInvalid(false); endField.setInvalid(false); durationField.setInvalid(false)
            return
        }
        startField.field.stringValue = formatTime(s)
        endField.field.stringValue = formatTime(e)
        durationField.field.stringValue = String(format: "%.3fs", e - s)
        startField.setInvalid(false); endField.setInvalid(false); durationField.setInvalid(false)
    }

    // MARK: - 解析与提交

    /// 支持 "mm:ss.mmm" 与纯秒 "12.4"
    private func parseTime(_ str: String) -> TimeInterval? {
        let s = str.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.contains(":") {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]),
                  m >= 0, sec >= 0, sec < 60 else { return nil }
            return m * 60 + sec
        }
        guard let v = Double(s), v >= 0 else { return nil }
        return v
    }

    @objc private func fieldAction(_ sender: NSTextField) {
        commit(sender)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        isEditing = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditing else { return }
        isEditing = false
        if let field = obj.object as? NSTextField {
            commit(field)
        }
    }

    private func commit(_ sender: NSTextField) {
        let senderIsStart = sender === startField.field
        let senderIsEnd = sender === endField.field
        let senderIsDuration = sender === durationField.field

        // 非当前编辑的框上残留的红框先按现有值重新校验，编辑的框按输入校验
        var newStart: TimeInterval?
        var newEnd: TimeInterval?

        func validate(_ field: ReadoutField, _ value: TimeInterval?) -> Bool {
            guard let v = value else {
                field.setInvalid(true)
                return false
            }
            if v < 0 || v > totalDuration + 0.001 {
                field.setInvalid(true)
                return false
            }
            field.setInvalid(false)
            return true
        }

        if senderIsStart {
            let v = parseTime(startField.field.stringValue)
            guard validate(startField, v), let s = v else { return }
            // 起点生效：终点 = max(输入, 现终点)；终点≤起点时拒绝
            let e = selectionEnd ?? totalDuration
            if s >= e - 0.001 {
                endField.setInvalid(true)
                startField.setInvalid(true)
                return
            }
            newStart = s; newEnd = e
        } else if senderIsEnd {
            let v = parseTime(endField.field.stringValue)
            guard validate(endField, v), let e = v else { return }
            let s = selectionStart ?? 0
            if e <= s + 0.001 {
                startField.setInvalid(true)
                endField.setInvalid(true)
                return
            }
            newStart = s; newEnd = e
        } else if senderIsDuration {
            let v = parseTime(durationField.field.stringValue.replacingOccurrences(of: "s", with: ""))
            guard validate(durationField, v), let d = v, d > 0.001 else {
                durationField.setInvalid(true)
                return
            }
            let s = selectionStart ?? 0
            let e = min(s + d, totalDuration)
            if e - s < 0.001 {
                durationField.setInvalid(true)
                return
            }
            newStart = s; newEnd = e
        }

        if let newStart, let newEnd {
            delegate?.selectionReadout(self, didCommitStart: newStart, end: newEnd)
        }
    }

    /// 当前选区（供 commit 联动用；由 Controller 每次 update 时同步）
    var selectionStart: TimeInterval?
    var selectionEnd: TimeInterval?

    private func formatTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, ms)
    }
}
