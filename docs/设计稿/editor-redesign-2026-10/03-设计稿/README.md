# editor-redesign-2026-10 · UI-018 交付目录

> 单号 UI-018：编辑页整体重设计——调研 + 两套设计稿（**只出设计，不改代码**）。
> **✅ 2026-10-16 11:14 老板拍板：方案 B（轨道主导，剪映式）**。A 稿留档不再推进；后续实现单（UI-019+）以 B 稿为唯一蓝本。
> 状态：设计稿 HTML 已完成并可直接交互；**PNG 导出与 git 落账待有 shell 的环境执行**（本班次 WorkBuddy 自动化沙箱无 shell，见 TODOS.md UI-018 blocked 记录）。

## 文件

| 文件 | 说明 |
|---|---|
| `../00-现状功能清单.md` | 编辑页现状 89 项功能盘点（源码行号级） |
| `../01-调研.md` | 7 款同类产品调研（22 条来源 URL，无杜撰） |
| `../02-设计原则.md` | 一页设计原则 |
| `04-功能落位对照表.md` | 现状功能 → 设计稿落位对照（无丢失证明） |
| `design-A.html` | 方向 A 文本主导（Descript 式），6 状态可切换 |
| `design-B.html` | 方向 B 轨道主导（剪映式），6 状态可切换 |
| `index.html` | A/B 整体预览页（切换单向 / 并排对比） |
| `规格表.md` | token 规格 + A/B 差异 + 拆单建议 + PNG 矩阵 |

## 看稿方式

浏览器打开 `index.html`（A/B 切换 + 并排对比）；每个 design-*.html 右上角可切 6 个必覆盖状态（④⑥ 有子态）。

## PNG 导出交接命令（有 shell 的会话执行；拍板后只导 B 稿 8 张，A 稿免导）

```bash
cd ~/Documents/workspace/AIAgent/projects/MicroPub
D=~/Documents/workspace/AIAgent/projects/audio_record_mac/docs/设计稿/editor-redesign-2026-10/03-设计稿
shot(){ node scripts/shot-card.mjs "$D/$1" "$D/pngs/$2"; }
mkdir -p "$D/pngs"
for s in 1 2 3 5; do
  shot "design-B.html?state=$s&clean=1" "B-0$s.png"
done
shot "design-B.html?state=4&clean=1" "B-04a-转写展开.png"
shot "design-B.html?state=4&fold=1&clean=1" "B-04b-转写折叠.png"
shot "design-B.html?state=6&sub=a&clean=1" "B-06a-转写进行中.png"
shot "design-B.html?state=6&sub=b&clean=1" "B-06b-无转写.png"
ls -la "$D/pngs"   # 8 张，每张 >50KB
```

> `shot-card.mjs` 按 `#shot` 元素裁切、@2x；两份 HTML 的画布即 `#shot`（1200×750）。最小尺寸（960×640）验证：浏览器手动缩窗目测分栏/轨道不破版，或再导 `&w=960` 变体（需脚本传 viewport，见 shot-card 用法）。

## git 落账交接命令（worktree 纪律）

```bash
cd ~/Documents/workspace/AIAgent/projects/audio_record_mac
git worktree add .worktrees/UI-018 -b loop/UI-018
mkdir -p ".worktrees/UI-018/docs/设计稿/editor-redesign-2026-10/03-设计稿/pngs"
mv docs/设计稿/editor-redesign-2026-10/*.md "docs/设计稿/editor-redesign-2026-10/03-设计稿/" 2>/dev/null
mv docs/设计稿/editor-redesign-2026-10/03-设计稿/*.html "docs/设计稿/editor-redesign-2026-10/03-设计稿/" 2>/dev/null
# ↑ 上一行如报「No such file」说明 md/html 已在 03-设计稿 下，跳过即可；核心是把整个目录移入 worktree：
mv docs/设计稿/editor-redesign-2026-10/* ".worktrees/UI-018/docs/设计稿/editor-redesign-2026-10/"
cd .worktrees/UI-018 && git add "docs/设计稿/editor-redesign-2026-10" && git commit -m "ui(UI-018): 编辑页整体重设计——调研+两套设计稿（含 PNG）"
```

> 注意：先跑 PNG 导出（产物落 `03-设计稿/pngs/`）再 mv+commit，一次收全。
