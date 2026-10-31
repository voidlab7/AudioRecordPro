import Foundation

// MARK: - ViewportResizeLock（UI-042）
/// 时间-像素映射锁定：窗口宽度变化时保持 pixelsPerSecond 恒定（对标剪映
/// 「拖动边框时轨道与时间标尺不动」），宽度变化只改变可见时间范围：
/// 拉宽 = 向右多露内容；拉窄 = 从右端裁掉内容。
///
/// 锚点口径（UI-042 细项 2 保守档，验收可改）：**锚左缘**——visibleStartTime
/// 保持不变，左缘内容钉住，「轨道不用动」最直观的语义。
///
/// 语义边界：
/// - 缩放级别由「最近一次显式缩放」（zoomIn/zoomOut/setZoomLevel/magnify/fitAll）
///   决定，与窗口宽度解耦——resize 不再重排波形、不再跳标尺档位
///   （TimeRulerView.rawStep = 80 / pps，pps 恒定 ⇒ 刻度间距与档位恒定）
/// - 允许 newDuration > totalDuration（拉宽超过全音频时长 = 全显 + 右端留白），
///   不强行重铺（重铺 = 波形重新拉伸，正是本单要消灭的行为）
public enum ViewportResizeLock {

    /// 可见时长下限（秒）：防极端窄窗产生无交互意义的微视口
    public static let minVisibleDuration: TimeInterval = 0.05

    /// 计算锁定映射后的新视口。
    /// - Parameters:
    ///   - oldWidth: 变化前的视口像素宽度（> 0）
    ///   - newWidth: 变化后的视口像素宽度（> 0 且 ≠ oldWidth 才需要调整）
    ///   - visibleStartTime: 当前可见时间起点（秒）
    ///   - visibleDuration: 当前可见时间长度（秒，> 0）
    ///   - totalDuration: 音频总时长（秒，> 0）
    /// - Returns: 新 (start, duration)；nil = 输入无效或宽度未变（无需调整）
    public static func resolve(
        oldWidth: CGFloat,
        newWidth: CGFloat,
        visibleStartTime: TimeInterval,
        visibleDuration: TimeInterval,
        totalDuration: TimeInterval
    ) -> (start: TimeInterval, duration: TimeInterval)? {
        guard oldWidth > 0, newWidth > 0, newWidth != oldWidth else { return nil }
        guard totalDuration > 0, visibleDuration > 0 else { return nil }

        // 锁定的映射：旧宽度 ÷ 旧可见时长 = 每秒像素数（resize 前后恒定）
        let lockedPPS = Double(oldWidth) / visibleDuration
        guard lockedPPS.isFinite, lockedPPS > 0 else { return nil }

        var newDuration = Double(newWidth) / lockedPPS
        if !newDuration.isFinite || newDuration < minVisibleDuration {
            newDuration = minVisibleDuration
        }

        var newStart = visibleStartTime
        if newDuration < totalDuration {
            // 部分可见：锚左缘，起点不越出音频尾部（右端 clamp 防视口滑出）
            newStart = max(0, min(visibleStartTime, totalDuration - newDuration))
        } else {
            // 全显或全显 + 右端留白：可视范围已覆盖全音频，起点归零
            newStart = 0
        }
        return (newStart, newDuration)
    }

    /// 锁定映射下的 pixelsPerSecond（波形与标尺共用同一换算，断言恒定用）
    public static func pixelsPerSecond(viewWidth: CGFloat, visibleDuration: TimeInterval) -> Double {
        guard viewWidth > 0, visibleDuration > 0 else { return 0 }
        return Double(viewWidth) / visibleDuration
    }
}
