# TODOS done 归档 · 2026-11 起

> 本文件由「验收即归档」规则（2026-10-12 老板定）生成：单子交付验收通过即从 `TODOS.md` 迁入此处，池里只留一行索引。
> 归档正文不再回改（历史事实记录）；回溯入口：本文件 / `git log --grep <单号>`。
> 2026-10 及更早历史：`TODOS-done-2026-10.md`、`TODOS-archive-20260920.md`。

---

### UI-042 拖动窗口边框时轨道与时间标尺不重排（时间-像素映射锁定） | P2 | S | [done · 2026-11-01 验收]

> 来源：老板 2026-10-31「需求入池，拖动边框的时候，轨道不用动。就是 轨道的标尺不用动。」+ 10-31「开始开发」=需求审核通过。
> 现状核实（10-31）：主窗口 `.resizable`（AppDelegate.swift:298），拖边框→宽度变化→①波形按新宽度重排（横向拉伸）②TimeRulerView 每次重绘按 `80px/pps` 自适应重算步长（TimeRulerView.swift:92-94 chooseNiceStep）→ 档位跳变（5s↔10s↔15s）。

**做什么**：锁定时间-像素映射（pixelsPerSecond 恒定），宽度变化只改变可见时间范围；波形不拉伸、标尺档位不跳变；显式缩放入口（Cmd 滚轮/捏合/fitAll/工具栏）行为不变。

**不做什么**：不改标尺/播放头 overlay 绘制（走同一条 viewport 同步链自动稳定）；不改显式缩放路径；不碰录制态实时条带。

**边缘情况**：拉宽越过全音频=全显+右端留白（不强行重铺）；极端窄窗可见时长触底 0.05s；起点越尾 clamp 到 totalDuration-duration；留白态 zoomLevel<1 的 UI 显示层钳制（控制器侧）。

**实现**（loop/UI-042，master 合并 807467d）：
- Kit 纯函数 `ViewportResizeLock.resolve`（锁定 pps/锚左缘保守档/右端 clamp/留白态/触底）+ 单测 9 例
- `EditorWaveformView.applyResizeLock(newWidth:)`（宽度基准 defer 无条件记录）+ `layout()` override 接线；zoomLevel 不变式同步（留白态可 <1）
- 控制器显示层钳制（zoomControls.zoomLevel=max(1,·)、visibleRatio 钳 1）
- lite 第 15 步 `resize_lock`（steps 14→15）：**真实窗口 setFrame 驱动**（完整 Auto Layout → layout() 全真实路径），断言 pps 恒定+锚左缘+niceStep 档位稳定+`header_frozen` 冻结首列+抗干扰重试

**验收期演进**（老板实机验收 3 轮反馈，全部收敛在验收轮内）：
1. R2 剪映轨道头截图 →「不用锁（不要锁定按钮功能），就是轨道头都不动，像是文档的冻结首行」→ 语义已成立（88px 常量约束+全源码零比例约束+虚拟滚动），升级为机器实证（header_frozen 断言，行内波形左缘两轮 resize 恒 88）
2. R3「滚动条超过头部了」→ 横向滚动条 leading 跳过 headerWidth(88) 与轨道内容区左缘对齐
3. R4 剪映参考图「有一个整体的布局块」→ TrackContainerView 加轨道头列整体背景块（标尺左段+带头+行间空隙连续底色，右缘 0.5px 分隔线贯穿全高，z 序最底）

**验收标准**：
- [x] 拖动窗口左/右缘：波形像素形态与标尺刻度间距保持稳定（刻度档位无 5s↔10s 跳变，波形不横向拉伸）——lite resize_lock pps 三轮精确恒等（342.92×3）+ step_stable + Kit 单测 9 例
- [x] 拖动中与松手后一致；多次 resize 后 fitAll / Cmd 缩放仍正常——纯函数即时收敛；锚点三轮恒等（0.993×3）；显式缩放路径零改动
- [x] `build-app.sh` exit 0；SDK 单测基线不回退；lite PASS——build 多轮 exit 0 / SDK 142/142（基线 133+9）/ lite 15/15（attempt=1 一次过）+ space_record + UITest2

**预估**：S ｜ **证据**：`docs/证据/2026-10-31-UI042-resize映射锁定-硬验证.md`（含 R2 轮记录）、`docs/LoopBuddy/R18-2026-10-31-战报.md`

**排障记录**（R1 lastLaidOutWidth 过期基准 = 3/7 分数形状定位；R2 三轮皆测试数学错位：redo 删除态 totalDuration 错位一半 / f0 基准越尾 clamp，App 实现零改动即正确——方法论：lite 断言期望值必须取被测视图实时状态）。

**实机验收项**：老板 10-31/11-01 实机拖边框+滚动条+布局块逐项看毕，「验收通过」（11-01）。合并态回归 build 0 / SDK 142/142；合并态 lite 待 App 空闲补跑（worktree 终版已 15/15）。
