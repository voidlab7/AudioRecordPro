import Foundation

// MARK: - UI-039: 编辑器空格键播放/暂停策略
/// 空格键事件的三态判定（无状态纯函数，可单测）。
/// 消费方：EditorViewController（局部事件监视器分发 + lite 自验第 14 步合成事件）。
///
/// 设计要点：
/// - 修饰键判定只显式查四个真实位（Cmd/Shift/Option/Ctrl），不做 subtracting 白名单——
///   合成/系统事件可能携带非标准 flag 位（R10 实测 0x2000_0000），subtracting 后永远非空
///   导致分支失活；显式位查询不受非标准位污染。
/// - 修饰键 rawValue 对应 NSEvent.ModifierFlags：control 1<<18、shift 1<<17、
///   option 1<<19、command 1<<20（硬编码避免 Kit 依赖 AppKit；调用方传
///   `event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue`）。
/// - 文本焦点判定（firstResponder 是否文本编辑视图）需要 AppKit 类型，留在 App 侧；
///   本策略只接收布尔结果。
/// - 三态语义：`.toggle` = 触发播放/暂停切换；`.swallowRepeat` = 长按连发帧吞掉
///   但不切换（按住空格只响应首个 keyDown）；`.passthrough` = 放行（组合键/文本输入/
///   非空格键，事件原样交给后续响应链）。
public enum SpaceKeyPolicy {

    /// 空格键 keyCode（kVK_Space）
    public static let spaceKeyCode: UInt16 = 49

    /// NSEvent.ModifierFlags.control.rawValue（1 << 18）
    static let controlRaw: UInt = 1 << 18
    /// NSEvent.ModifierFlags.shift.rawValue（1 << 17）
    static let shiftRaw: UInt = 1 << 17
    /// NSEvent.ModifierFlags.option.rawValue（1 << 19）
    static let optionRaw: UInt = 1 << 19
    /// NSEvent.ModifierFlags.command.rawValue（1 << 20）
    static let commandRaw: UInt = 1 << 20

    public enum Decision: Equatable {
        /// 触发播放/暂停切换
        case toggle
        /// 吞掉但不切换（长按连发帧）
        case swallowRepeat
        /// 放行（事件继续走后续分发）
        case passthrough
    }

    /// 空格键事件判定
    /// - Parameters:
    ///   - keyCode: `event.keyCode`
    ///   - rawModifiers: `event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue`
    ///   - isARepeat: `event.isARepeat`
    ///   - textEntryFocus: 窗口 firstResponder 是否文本编辑视图（field editor / 可编辑
    ///     NSTextField / NSTextView），App 侧判定
    public static func decide(keyCode: UInt16,
                              rawModifiers: UInt,
                              isARepeat: Bool,
                              textEntryFocus: Bool) -> Decision {
        guard keyCode == spaceKeyCode else { return .passthrough }
        let hasRealModifier = rawModifiers & (commandRaw | shiftRaw | optionRaw | controlRaw) != 0
        if hasRealModifier { return .passthrough }   // Cmd/Shift/Option/Ctrl 组合不拦截
        if textEntryFocus { return .passthrough }    // 输入框聚焦时空格保持正常输入
        if isARepeat { return .swallowRepeat }       // 长按不连发
        return .toggle
    }
}
