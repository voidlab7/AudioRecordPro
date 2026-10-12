import XCTest
@testable import AudioRecordKit

/// FEAT-002：txt 导出纯文本生成器单测
/// plainText 与 markdown 同在 TranscriptPanelView（App 层），该文件已加入本 target sources
final class TranscriptExportTests: XCTestCase {

    private func makeTranscript(segments: [TranscriptSegment]) -> Transcript {
        Transcript(locale: "zh-CN", engine: "AppleSpeechTranscriber", segments: segments)
    }

    /// txt 输出必须无任何 Markdown 标记（对照 markdown() 版本的 `**` / `- ` / `---` / `*斜体*`）
    func testPlainTextHasNoMarkdownMarkers() {
        let t = makeTranscript(segments: [
            TranscriptSegment(start: 5.2, end: 8.0, text: "第一段内容"),
            TranscriptSegment(start: 63.0, end: 70.5, text: "第二段内容"),
        ])
        let txt = TranscriptPanelView.plainText(for: t, fileName: "会议记录")

        XCTAssertFalse(txt.contains("**"), "txt 不应含粗体标记")
        XCTAssertFalse(txt.contains("\n---\n"), "txt 不应含水平分割线语法")
        XCTAssertFalse(txt.contains("*由"), "txt 不应含斜体署名语法")
        for line in txt.split(separator: "\n") {
            XCTAssertFalse(line.hasPrefix("- "), "txt 不应含列表语法: \(line)")
            XCTAssertFalse(line.hasPrefix("#"), "txt 不应含标题语法: \(line)")
        }
    }

    /// txt 输出结构：标题行、全文、带 [MM:SS] 时间戳的分段、署名
    func testPlainTextStructure() {
        let t = makeTranscript(segments: [
            TranscriptSegment(start: 5.2, end: 8.0, text: "第一段内容"),
            TranscriptSegment(start: 63.0, end: 70.5, text: "第二段内容"),
            TranscriptSegment(start: 70.5, end: 71.0, text: ""),  // 空段应被跳过
        ])
        let txt = TranscriptPanelView.plainText(for: t, fileName: "会议记录")

        XCTAssertTrue(txt.hasPrefix("会议记录\n"), "首行应为文件名")
        XCTAssertTrue(txt.contains("【全文】\n第一段内容第二段内容"), "全文区块（CJK 无空格拼接）")
        XCTAssertTrue(txt.contains("【分段】"))
        XCTAssertTrue(txt.contains("[00:05] 第一段内容"), "时间戳应格式化为 MM:SS")
        XCTAssertTrue(txt.contains("[01:03] 第二段内容"), "63 秒应为 01:03")
        XCTAssertFalse(txt.contains("70.5"), "空文本段不应输出")
        XCTAssertTrue(txt.contains("由 Loocap 本机转写生成"))
    }

    /// 单段文稿不输出【分段】区块
    func testPlainTextSingleSegmentOmitsSection() {
        let t = makeTranscript(segments: [
            TranscriptSegment(start: 0, end: 10, text: "只有一段"),
        ])
        let txt = TranscriptPanelView.plainText(for: t, fileName: "备忘")

        XCTAssertFalse(txt.contains("【分段】"))
        XCTAssertTrue(txt.contains("【全文】\n只有一段"))
    }
}
