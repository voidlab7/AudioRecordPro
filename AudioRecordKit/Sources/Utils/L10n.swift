import Foundation

// MARK: - 本地化基础设施（国际版 i18n）
//
// 设计约定：
// 1. 源码 key = 中文原文（zh-Hans 为 base 文案）——中文环境零迁移成本、行为零变化
// 2. 英文环境从 en.lproj/Localizable.strings 取翻译；查不到时原样返回 key（中文），不会崩
// 3. 带参文案使用 %@ / %d 等占位符，配合 localized(_ args:) 使用
// 4. 严禁把动态拼接文案整体当 key（如 "正在播放: \(name)"）——参数必须用占位符
// 5. 逻辑判断严禁依赖本地化后的显示文案（REL-002 已解耦：状态走 RecordingState
//    枚举通道 onStateChange，StatusBarView 纯展示）

extension String {
    /// 无参本地化
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// 带参本地化：key 内含 %@ / %d 等格式占位符
    func localized(_ args: CVarArg...) -> String {
        String(format: localized, arguments: args)
    }
}
