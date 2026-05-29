# AudioRecordMac 文档索引

> 更新时间：2026-05-21  
> 状态：已重组为"入口索引 + 当前知识库 + 执行文档 + 历史归档"。旧的 `AudioRecordApp知识库.md` 已拆分到 `knowledge/`。
## 当前事实源优先级

| 优先级 | 文档 / 目录 | 用途 | 状态 |
|---|---|---|---|
| 1 | `../AudioRecordApp/`、`../AudioRecordKit/` | 实际代码事实源 | 当前有效 |
| 2 | `knowledge/README.md` | 当前知识库入口 | **当前主入口** |
| 3 | `knowledge/product.md` | 产品定位、目标用户、版本需求全景 | 当前有效 |
| 4 | `knowledge/ux.md` | UI / 交互 / 信息架构事实源 | 当前有效 |
| 5 | `knowledge/tech.md` | 技术架构、录制、编辑器、文件导出 | 当前有效 |
| 6 | `knowledge/risks.md` | 风险、技术债、代码事实差异、QA 重点 | 当前有效 |
| 7 | `requirements/README.md` | V1.x / V2.0 需求列表与状态 | 执行事实源 |
| 8 | `design/`、`architecture/` | 当前 UI 设计和技术方案细节 | 当前有效，需结合 `knowledge/` 使用 |
| 9 | `product/`、`research/` | 产品路线、定位建议、竞品研究 | 参考资料 |
| 10 | `archive/` | 历史方案、迁移资料、旧设计 | 归档资料 |

## 目录职责

| 目录 / 文件 | 职责 |
|---|---|
| `README.md` | 文档总入口，只做导航和事实源规则 |
| `knowledge/` | 当前项目主知识库，按产品、UX、技术、风险拆分 |
| `requirements/` | 可执行需求单、优先级、状态、验收标准 |
| `design/` | 当前有效 UI / 交互设计方案 |
| `architecture/` | 当前有效技术架构和专项技术评估 |
| `product/` | 产品路线、产品定位、V1 功能细化 |
| `research/competitors/` | 竞品分析和外部参考 |
| `bugs/` | 具体问题记录和修复追踪 |
| `reviews/` | 阶段评审、QA 报告、验收报告 |
| `archive/` | 过期方案、旧设计、迁移历史，仅作参考 |
| `AudioRecordApp知识库.md` | 兼容旧链接的跳转索引，不再作为主事实源维护 |

## 快速查找

| 问题 | 先看 |
|---|---|
| 产品是什么、给谁用、版本怎么排 | `knowledge/product.md` |
| UI 为什么重叠、录制态 / 编辑态怎么区分 | `knowledge/ux.md` |
| 录音目录在哪里、导出和格式转换怎么做 | `knowledge/tech.md` |
| 当前有哪些风险、代码和文档哪里不一致 | `knowledge/risks.md` |
| 某个需求是否完成、验收标准是什么 | `requirements/README.md` 和具体 `REQ-*.md` |
| 编辑器 UI 细节 | `design/V1.1-编辑器UI设计方案.md` |
| 设计系统（颜色、字体、组件规范） | `design/design-system.md` |
| 编辑器技术细节 | `architecture/V1.1-编辑器技术方案评估.md` |
| UI 架构分析（视图层级、面板管理） | `architecture/ui-analysis-detailed.md` |
| UI 设计与架构探索报告 | `architecture/ui-architecture-exploration.md` |
| 产品路线和早期功能拆解 | `product/` |
| Landing Page 策略 | `product/landing-page-strategy.md` |
| 宣发策略（分阶段） | `product/marketing-strategy-phased.md` |
| 竞品参考 | `research/competitors/` |

## 文档使用规则

1. 讨论产品、UI、交互、技术方案时，先读 `knowledge/README.md`。
2. 讨论具体需求编号和排期时，读 `requirements/README.md`。
3. 讨论 UI 落地细节时，再读 `design/`。
4. 讨论底层技术细节时，再读 `architecture/`。
5. 若文档与代码冲突，以实际代码为准，并同步更新 `knowledge/` 对应文件。
6. 后续不要继续新增多个互相冲突的 UI 草案；优先更新 `knowledge/ux.md` 和 `design/`。

## 最近重组

| 调整 | 结果 |
|---|---|
| 拆分总知识库 | `AudioRecordApp知识库.md` → `knowledge/product.md`、`knowledge/ux.md`、`knowledge/tech.md`、`knowledge/risks.md` |
| 产品资料归类 | `产品路线图.md`、`产品定位建议_顾问隐.md`、`V1_功能细化.md` → `product/` |
| 竞品资料归类 | `竞品分析_*.md` → `research/competitors/` |
| 根目录收敛 | 根目录只保留入口和兼容索引，业务内容进入对应目录 |
| 根目录文档归入知识库 | `DESIGN.md` → `design/design-system.md`、`Landing-Page-策略.md` → `product/landing-page-strategy.md`、`UI_ANALYSIS_DETAILED.md` → `architecture/ui-analysis-detailed.md`、`UI_ARCHITECTURE_EXPLORATION.md` → `architecture/ui-architecture-exploration.md`、`宣发策略-分阶段.md` → `product/marketing-strategy-phased.md` |

## 归档文档

| 目录 | 内容 | 用途 |
|---|---|---|
| `archive/mvp-api/` | MVP API、MediaStream、兼容 Web API 等早期草案 | 历史决策依据 |
| `archive/migration/` | SDK/App 分离迁移方案、文件依赖分析 | 迁移历史 |
| `archive/design-proposals/` | 早期 UI 重设计方案 | 备选参考，不作为当前事实源 |
| `archive/strategy/` | 早期战略评审草稿 | 历史参考 |
| `archive/old-designs/`、`archive/old-product-docs/` | 旧 UI / 产品文档 | 历史参考 |
