# FEAT-001：语音转文字（录音 → 文字 → App 内查看 → 导出 MD）

> 调研：小J（Jarvis）｜2026-10-11｜老板诉求：录完音频转文字，**越快越好 + 越准越好**，App 内直接看，可导出 Markdown。
> 状态：**方案草案，待老板签验收标准后开工**（Loop 纪律）。
> 附录：全球引擎成本/精度/语言支持整理版见 `FEAT-001-附录-全球STT引擎成本与精度对比.md`（2026-10-11 老板要求整理）。

---

## 一、结论（先行）

**双引擎架构，默认走 Apple 原生，高精模式走 whisper.cpp：**

| 层 | 引擎 | 角色 |
|---|---|---|
| 默认（快） | **Apple SpeechAnalyzer / SpeechTranscriber**（macOS 26 原生 API） | 录音中**实时出字**、录完秒转；零成本、零上传、模型系统托管（不占 App 体积） |
| 高精（准） | **whisper.cpp + large-v3-turbo**（Metal GPU） | 「高精度模式」按钮触发；Apple 模型不可用时的兜底；词级时间戳 |
| 兜底 | DictationTranscriber（同框架旧引擎） | SpeechTranscriber 不支持的语言/设备时自动降级 |

**不选的**：云 API（OpenAI/讯飞）——上传隐私 + 按分钟付费，且产品路线图明确定位「本地模型」为差异化卖点；Parakeet——无中文；Qwen3-ASR——中文最准但生态/集成成本高，记入未来观察池。

## 二、本机与竞品事实（2026-10 最新数据）

### 本机条件（已实测确认）
- **M4 Pro + macOS 26.2**：SpeechAnalyzer 全功能可用（它就是系统「语音备忘录/备忘录」App 用的引擎）
- M4 Pro 跑 whisper.cpp large-v3-turbo（Metal）约 **16x 实时**：1 小时录音 ≈ 4 分钟转完

### 精度对标（FLEURS 基准，同机同测试集，错字率越低越好）

| 引擎 | 中文 CER | 英文 WER | 速度 | 成本 |
|---|---|---|---|---|
| **Apple Speech（新引擎）** | 7.97 | 8.80 | **~3x 于 Whisper Small，2.2x 于 Large V3** | 免费 |
| whisper.cpp large-v3-turbo | 7.97（Large 级） | **10.0（最优档）** | 6-16x 实时（Metal） | 免费，模型 1.5GB 按需下载 |
| Qwen3-ASR | **6.49（中文最准）** | 4.49 | 中等 | 免费，集成成本高 |
| Whisper Small（MicroTranscribe 现用） | 20.50 ❌ | 7.04 | 快 | 免费 |
| Apple 旧听写（DictationTranscriber） | 10.28 | 13.83 | 快 | 免费 |

> 关键判断：**中文场景 Apple 新引擎与 Whisper Large 打平（7.97），但速度完胜**；whisper.cpp turbo 在英文/混合场景更准。默认+高精双引擎覆盖「快」和「准」两个诉求，无冲突。

## 三、已有资产（不重复造轮子）

| 资产 | 位置 | 可复用点 |
|---|---|---|
| MicroTranscribe 脚本管线 | `projects/MicroTranscribe/` | faster-whisper 转写逻辑参考（脚本层，09-20 实战验证）；注意其 small 模型中文 CER 20.5，**App 内不用** |
| audio-transcribe 技能 | `SKILL仓库/工程与运维/` | 环境坑清单（ffmpeg/模型缓存/HF 镜像） |
| 产品路线图 V2.0 规划 | `research/insights/产品idea/idea-03-*/产品路线图.md` | 早已规划「whisper.cpp + CoreML、录完一键转、Pro 功能」——本 REQ 是它的落地 |

## 四、技术方案

### 4.1 引擎抽象（Swift 协议）

```swift
protocol TranscriptionEngine {
    func transcribe(url: URL, progress: @escaping (Double) -> Void) async throws -> Transcript
    // Transcript = [Segment { start, end, text }]
}
```

- `AppleSpeechEngine`：`SpeechAnalyzer` + `SpeechTranscriber`（macOS 26+；`DictationTranscriber` 降级路径）
- `WhisperCppEngine`：whisper.cpp SPM 依赖 + Metal，ggml-large-v3-turbo 模型**首次使用时下载**（1.5GB，不进 App bundle）

### 4.2 关键集成要点（官方坑，抄作业）

1. **顺序铁律**：实例化 transcriber → `AssetInventory.assetInstallationRequest()` 下载语言资产 → `transcriber.allocate(locale:)` → 创建 analyzer → `bestAvailableAudioFormat` → start。**allocate 必须在下载之后**，否则报 `unallocated locales`
2. 音频 buffer 用 `AVAudioConverter` 转（`primeMethod = .none`，防时间戳漂移）
3. `reportingOptions: [.volatileResults]` → 录音中实时出字（volatile 中间结果 + isFinal 定稿）
4. `attributeOptions: [.audioTimeRange]` → 词级时间戳，MD 导出和「点击文字跳转音频」都靠它
5. 语言资产是 macOS 系统级下载（用户首次使用时系统拉取，含中文 zh-CN）

### 4.3 App 内交互（三步）

1. **录音页**：录制中底部实时滚动出字（volatile 结果灰显、定稿黑字）
2. **转写页签**：文件列表每条音频带「转文字」按钮 → 进度条 → 完成后侧栏新增「文稿」页签，时间轴分段展示（点段落跳音频对应位置，复用现有 WaveformView 定位）
3. **导出 MD**：一键导出，格式——

```markdown
# 录音转写 · 2026-10-11 14:30
> 来源：xxx.wav ｜ 时长 45:12 ｜ 引擎：Apple Speech
## [00:00] 第一段
正文……
## [03:12] 第二段
正文……
```

### 4.4 降险第一步（0 代码成本）

先装 `yap` CLI（macOS 26 SpeechAnalyzer 的官方路径命令行工具），拿两条真实中文录音实测效果——**半小时内出结论，验证不过再调整引擎配比**，不写一行 Swift。

## 五、验收标准（草案，待老板签）

- [ ] yap CLI 实测：2 条真实中文录音转写可用，老板主观认可准确率
- [ ] 对 5 分钟中文录音：Apple 引擎转写耗时 ≤ 30s（M4 Pro 实测基准）
- [ ] 录音中实时出字：说话后 ≤ 2s 出现 volatile 文本，停止后定稿
- [ ] App 内文稿页签：分段 + 时间戳展示，点击段落跳转音频位置
- [ ] 导出 MD：文件含标题元信息 + 时间戳分段，Typora/微信传输打开正常
- [ ] 高精模式：whisper.cpp turbo 可选触发，英文录音 WER 主观优于默认引擎
- [ ] 全程离线（断网转写成功），无任何网络上传
- [ ] `build-app.sh` exit 0；回归 TC-001 主链路 PASS

## 六、云端引擎对比与「本地 vs 云端」验证方案（2026-10-11 补，老板要求）

### 6.1 云端行情（2026-09 官网口径，签前以官网为准）

| 服务 | 批量转写价 | 特点 |
|---|---|---|
| **阿里百炼 Paraformer/Fun-ASR** | **¥0.288/小时（全场地板价）** | 中文 CER ~4.56%（Paraformer-Large，比 Apple/Whisper Large 都准）；支持热词定制；批量流式同价 |
| 阿里 Qwen3-ASR-Flash | ~¥1.1/小时 | 中文最准档（FLEURS 6.49）；流式/方言 |
| 腾讯云录音文件识别 | ¥0.7~1.2/小时（大模型版 ~0.8） | 每月送 10 小时免费；稳定性好 |
| 火山豆包（Seed-ASR） | ~¥1/小时 | 中英混说/上下文感知强 |
| 讯飞 | ¥4.9~9.9/小时 | 偏贵；免费 5 小时/月 |
| OpenAI gpt-4o-mini-transcribe | ~¥1.3/小时（$0.18） | 最便宜的海外档；中文不如国产 |
| OpenAI whisper-1 | ~¥2.6/小时（$0.36） | **唯一带词级时间戳**的 OpenAI 模型 |
| AWS Transcribe | ~¥10/小时 | 最贵，不考虑 |

> 个人用量参考：每月转 20 小时，最便宜的云端方案 **≈ ¥6/月**；重度 50 小时 ≈ ¥14/月。成本对个人不是问题，**对产品定价才是问题**——本地 = 边际成本 0，云端 = 每小时持续出血。

### 6.2 云端相对本地的真实优势（不只是精度）

1. **精度**：Paraformer 中文 4.56% vs 本地最好 7.97%——差 3.4 个百分点，会议场景可感知
2. **说话人分离（diarization）**：云端普遍带，本地双引擎都没有——「谁说了什么」对会议纪要是刚需
3. **热词/术语定制**：Paraformer 支持注入专业词汇表
4. 云端劣势：隐私上传、断网不可用、持续计费、延迟受网络波动（1-5s）

### 6.3 验证实验设计（老板拍板后执行，预计半天）

**固定测试集**（3 条真实录音，各 5-10 分钟）：
- A：安静环境中文会议/对话　B：中英混合（技术讨论）　C：嘈杂/远场（系统声音+环境音）

**候选引擎**（5 个，免费额度全覆盖测试成本）：
| 引擎 | 类型 | 成本 |
|---|---|---|
| Apple SpeechAnalyzer | 本地 | 0 |
| whisper.cpp large-v3-turbo | 本地 | 0 |
| 阿里 Paraformer | 云端 | 测试期免费额度 |
| 阿里 Qwen3-ASR | 云端 | 测试期免费额度 |
| 腾讯云录音文件识别 | 云端 | 每月免费 10 小时 |

**评测维度**（每引擎 × 每条录音）：
- 准确率：人工抽校 200 字计算错字率（无标注集就按此简化法）
- 速度：端到端耗时（本地测 M4 Pro 实机，云端含上传）
- 成本：折算 ¥/小时
- 附加：词级时间戳有无、说话人分离有无、断点续转

**裁决规则（预注册，防事后合理化）**：
- 云端中文准确率领先 **>2 个百分点** 且单小时成本 ≤¥1 → 云端作为「Pro 高精模式」可选引擎保留（用户自带 API Key 或订阅内含额度），本地仍为默认
- 领先 ≤2pp → 云端不进产品，本地双引擎终版；表格归档作为后续重评基线
- 无论结果如何，引擎协议不变——云端只是 `TranscriptionEngine` 的第三个实现，随时可加可摘

### 6.4 若市场切换为「海外 / 英文为主」（2026-10-11 补，老板追问）

**英文基准（FLEURS，错字率越低越好）**：Qwen3-ASR 4.49 → Whisper Large 5.49 → Parakeet 6.89 → Whisper Small 7.04 → **Apple Speech 8.80**。whisper.cpp large-v3-turbo 在嘈杂实测集 WER 10%，干净语音 3-5%。

结论变化四条：

1. **本地引擎主次对调**：英文场景 Apple Speech（8.80）**输给** Whisper Large 级（5.49）——whisper.cpp large-v3-turbo 升为**英文默认/首选引擎**，Apple 退居「实时字幕流」（说话时边录边出字仍是它独有优势）。中文场景则相反（Apple 与 Large 打平且快 3 倍）。→ 引擎选择应**按检测语言自动路由**，协议已支持。
2. **Parakeet 值得入候选池**：英文专用速度王（RTF 0.017 ≈ 50x 实时，M4 资源占用最低 870MB），FluidAudio 有现成 Swift 绑定——实时听写场景可作第三本地引擎。中文不支持，仅英文市场用。
3. **云端格局换血**：海外云端便宜且快——Groq 托管 Whisper **$0.02-0.10/小时**（比 OpenAI 便宜 4-18 倍，速度快 7 倍）、AssemblyAI Universal-2 $0.15/h、Deepgram Nova-3 $0.26/h。OpenAI 反而不占优。英文云端与本地精度差距缩小（Whisper Large 本地≈云端同权重），云端剩余价值 = diarization + 免配置。
4. **市场/合规红利**：海外用户隐私敏感度更高，「local-only、no cloud」是 MacWhisper（$29 买断）验证过的核心卖点；收款走 Stripe/Paddle 无国内合规负担；订阅 $9.99/月 全本地交付 = 毛利 ~100%，云端只做可选增值（Pro 用户自带 Groq/OpenAI Key 模式，零成本转售风险）。

**验证集相应调整**：C 场景改为「英文会议/播客」，引擎池改为 Apple + whisper.cpp turbo + Parakeet（本地）× Groq + AssemblyAI（云端），裁决规则不变（云端领先 >2pp 且 ≤$0.15/h 才进产品）。

**双市场终局形态**：一套 App，检测语言 → 本地引擎自动路由（中文→Apple Speech 优先，英文→whisper.cpp turbo 优先），云端作为可选 Pro 引擎按区域接入（国内阿里 Paraformer / 海外 Groq）。协议层零改动，只是多两个实现。

### 6.5 产品视角的定价含义

路线图定位 Pro $9.99/月 含转写。若云端进产品：按重度用户 50h/月算，Paraformer 成本 ~¥14/月，占订阅收入 20%——可接受但要设额度上限；**本地免费无限转**仍是核心卖点（MacWhisper 买断 $29 只做转写无录制，我们的组合是差异化）。

## 七、工作量预估

| 步骤 | 内容 | 量 |
|---|---|---|
| S0 | yap 实测验证 | 0.5h（本机即可做） |
| S1 | AppleSpeechEngine + 实时流 | 1 天 |
| S2 | 文稿 UI（页签/段落/跳转） | 1-1.5 天 |
| S3 | MD 导出 | 0.5 天 |
| S4 | WhisperCppEngine 高精模式 | 1 天（可后置为独立单） |

> 建议 S0-S3 为一张单（FEAT-001），S4 拆独立单后排池。
