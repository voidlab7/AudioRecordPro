import XCTest
@testable import AudioRecordKit

/// UI-039 硬验证：编辑器空格键播放/暂停策略（三态判定纯函数）。
/// 断言六件事：
/// 1) 纯空格（无修饰键、非 repeat、无文本焦点）→ .toggle
/// 2) 长按连发帧 → .swallowRepeat（按住空格只响应首个 keyDown）
/// 3) 文本输入焦点 → .passthrough（输入框内空格保持正常输入，不误触播放）
/// 4) 四个真实修饰键（Cmd/Shift/Option/Ctrl）各自组合 → .passthrough
/// 5) 非空格键 → .passthrough
/// 6) R10 坑1 回归：非标准 flag 位（0x2000_0000，合成/系统事件实测携带）不污染判定
final class SpaceKeyPolicyTests: XCTestCase {

    private let space = SpaceKeyPolicy.spaceKeyCode

    func testPlainSpaceToggles() {
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: 0,
                                             isARepeat: false, textEntryFocus: false),
                       .toggle)
    }

    func testRepeatSwallowedNotToggled() {
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: 0,
                                             isARepeat: true, textEntryFocus: false),
                       .swallowRepeat)
    }

    func testTextEntryFocusPassesThrough() {
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: 0,
                                             isARepeat: false, textEntryFocus: true),
                       .passthrough)
    }

    func testEachRealModifierPassesThrough() {
        // 对应 NSEvent.ModifierFlags：control 1<<18 / shift 1<<17 / option 1<<19 / command 1<<20
        let modifiers: [String: UInt] = [
            "control": 1 << 18,
            "shift": 1 << 17,
            "option": 1 << 19,
            "command": 1 << 20,
        ]
        for (name, raw) in modifiers {
            XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: raw,
                                                 isARepeat: false, textEntryFocus: false),
                           .passthrough, "\(name)+Space 必须放行")
        }
        // 组合（Cmd+Shift）同样放行
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: (1 << 20) | (1 << 17),
                                             isARepeat: false, textEntryFocus: false),
                       .passthrough)
    }

    func testNonSpaceKeyPassesThrough() {
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: 12, rawModifiers: 0,
                                             isARepeat: false, textEntryFocus: false),
                       .passthrough)
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: 123, rawModifiers: 0,
                                             isARepeat: false, textEntryFocus: false),
                       .passthrough)
    }

    func testNonStandardFlagBitDoesNotPollute() {
        // R10 坑1 回归：合成 CGEvent→NSEvent 携带非标准位 0x2000_0000，
        // deviceIndependentFlagsMask 交集后仍在——显式位判定不受污染，纯空格仍命中。
        let polluted = UInt(0x2000_0000)
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: polluted,
                                             isARepeat: false, textEntryFocus: false),
                       .toggle)
        // numericPad（1<<21）/function（1<<23）/capsLock（1<<16）等非"真实修饰键"位同理不拦截
        XCTAssertEqual(SpaceKeyPolicy.decide(keyCode: space, rawModifiers: 1 << 21,
                                             isARepeat: false, textEntryFocus: false),
                       .toggle)
    }
}
