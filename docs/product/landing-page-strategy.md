# Recording App - Landing Page 策略

## 目标
在 App Store 上架前，先做一个 Landing Page，用来：
1. **验证需求**（环节①）- 收集 Email Waitlist
2. **SEO 获客**（环节④）- 让 Google 收录关键词
3. **Product Hunt 发布**（环节④）- 给用户一个完整的产品介绍页
4. **数据复盘**（环节⑥）- 看访问量/转化率，判断是否值得继续

---

## Landing Page 核心结构

### Hero Section（英雄区）
```
标题: Record Any Sound on Mac. Transcribe in 1-Click.
副标题: System audio · App audio · Microphone. All in one app.
CTA: Download for Mac (或 Join Waitlist 如果还没上架)
视频/动图: 30 秒演示录制 → 转文字 → 复制
```

**关键词优化:**
- Title tag: "Mac Audio Recorder with AI Transcription - [App Name]"
- Meta description: "Record system audio, app audio, or microphone on Mac. Transcribe to text in 1-click with local Whisper AI. No cloud, no subscription."

---

### Problem-Solution（问题-解决方案）
```
标题: You Can't Download It, But You Can Record It.

卡片 1: YouTube/网课/会议 无法下载
  → ✅ 播放时录制系统音频

卡片 2: 需要会议纪要/学习笔记
  → ✅ 一键转文字（本地 Whisper）

卡片 3: 竞品 UI 太丑 or 功能太复杂
  → ✅ 简洁 UI + 刚好够用的功能
```

---

### Features（功能展示）
```
用图标 + 1 句话说清楚：

🎙️ System Audio Recording
   Record any sound playing on your Mac

📱 App-Specific Recording
   Record audio from specific apps only

🎤 Microphone + Mix
   Record your voice with system audio

✂️ Simple Editing
   Trim, normalize, remove silence

🤖 AI Transcription
   Whisper AI, local, free, 99 languages

💾 Export Formats
   M4A / WAV / MP3 / TXT / SRT
```

---

### Use Cases（使用场景）
```
标题: Who Uses [App Name]?

🎙️ Podcasters
   Record remote interviews from Zoom/Teams

🎓 Students
   Record online courses and transcribe to notes

💼 Professionals
   Record meetings and generate transcripts

🎵 Musicians
   Record system audio for sampling

🎮 Streamers
   Record game audio separately
```

---

### Pricing（定价）
```
标题: Simple Pricing. No Subscription.

免费版: 5 分钟录制限制
Pro 版: ¥98 一次性买断，无限录制 + AI 转文字

CTA: Download Now
```

---

### Social Proof（社会证明）
```
如果有用户评价/测试反馈：
  "Best audio recorder I've used on Mac" - @username

如果没有：
  暂不放这个区块，等上架后有评价再加
```

---

### FAQ（常见问题）
```
Q: 需要联网吗？
A: 不需要。Whisper AI 在本地运行，隐私安全。

Q: 支持什么语言？
A: Whisper 支持 99 种语言，包括中文/英文/日文等。

Q: 和 Audio Capture Pro 有什么区别？
A: 我们有 AI 转文字 + 更好的 UI + 轻编辑功能。

Q: 为什么要买断而不是订阅？
A: 我们相信工具应该一次付费，终身使用。
```

---

## 技术实现

### 方案 1: 静态页面（推荐，最快）
```
技术栈: HTML + Tailwind CSS + 部署到 Vercel/Netlify
时间: 1 天
成本: 免费

优势:
  - 极快（几小时可以上线）
  - SEO 友好
  - 不需要后端

劣势:
  - 如果要收集 Email Waitlist，需要集成第三方服务（Mailchimp/ConvertKit）
```

### 方案 2: Next.js + Vercel（灵活）
```
技术栈: Next.js + Tailwind + Vercel
时间: 2-3 天
成本: 免费（Vercel Hobby Plan）

优势:
  - 可以加 Waitlist 功能（存到 Supabase/Airtable）
  - 可以加简单的博客（SEO 内容营销）
  - 可以 A/B 测试不同的文案

劣势:
  - 开发时间稍长
```

### 推荐: 方案 1（静态页面）
**原因:**
- 您现在需要快速验证，不需要复杂功能
- 等 App 上架后，Landing Page 就直接跳转到 App Store
- 不需要 Waitlist（因为 App 很快就能上架）

---

## SEO 关键词策略

### 核心关键词（英文）
```
Primary:
  - mac audio recorder
  - system audio recorder mac
  - record system audio mac

Secondary:
  - audio transcription mac
  - mac screen recording audio
  - record zoom audio mac
```

### 内容策略（博客/帮助文档）
```
如果有时间，可以写 3-5 篇教程博客（每篇 1h）:

1. "How to Record System Audio on Mac (2026 Guide)"
   → SEO 流量词，带到 Landing Page

2. "Best Mac Audio Recorders Compared (2026)"
   → 竞品对比，突出自己的优势

3. "How to Transcribe Audio to Text on Mac (Free)"
   → 转文字教程，引流到产品

4. "Record Zoom Meetings on Mac: Complete Guide"
   → 场景化教程

5. "Mac Audio Recording: App vs System vs Microphone"
   → 教育用户，建立权威
```

---

## Product Hunt 发布（环节④的重点）

### 准备清单
```
发布前 2 周:
  - [ ] Landing Page 上线
  - [ ] 5 张精美截图（工业风 UI）
  - [ ] 30 秒演示视频（录制 → 转文字 → 复制）
  - [ ] 产品描述（200 字）
  - [ ] Tagline（1 句话）: "Record any sound on Mac. Transcribe in 1-click."

发布当天:
  - [ ] 早上 8:00 发布（PST 时区）
  - [ ] 在 Reddit/X/微信群 求 upvote
  - [ ] 回复所有评论（至少前 24 小时）

发布后:
  - [ ] 看 Landing Page 流量 spike
  - [ ] 看有多少人点击 "Download"
  - [ ] 收集反馈 → 快速迭代
```

---

## 数据复盘（环节⑥）

### 跟踪指标
```
上架前（Landing Page 阶段）:
  - Landing Page 访问量: ？PV/天
  - 点击 "Download" 按钮: ？次
  - 转化率: ？%

上架后（App Store 阶段）:
  - App Store 页面访问: ？次
  - 下载量: ？次
  - 付费转化: ？人
  - 付费率: ？%

工具:
  - Google Analytics（Landing Page）
  - App Store Connect（下载数据）
```

### 决策标准
```
2 周后看数据:
  ✅ Landing Page 日访问 > 50 + 下载转化 > 10% → 继续
  ⚠️ 访问 < 20 or 转化 < 5% → 调整文案/SEO
  ❌ 完全没流量 → 说明获客渠道有问题，重新思考

4 周后看付费:
  ✅ 付费用户 > 10 人 → PMF 初步验证，进入增长期
  ⚠️ 付费 < 5 人 → 价格/功能有问题，调整
  ❌ 0 付费 → 要么免费要么放弃
```

---

## 执行时间表

### Week 1: Landing Page 上线
- [ ] Day 1-2: 写文案 + 设计（用 UI-Prompt 生成）
- [ ] Day 3: 开发静态页面
- [ ] Day 4: 部署到 Vercel，绑定域名
- [ ] Day 5: SEO 设置（Google Search Console）

### Week 2-3: App 开发（并行）
- [ ] 开发 App 的同时，Landing Page 开始做 SEO

### Week 4: Product Hunt 发布
- [ ] 准备素材
- [ ] 发布当天冲榜
- [ ] 看 Landing Page 流量 spike

---

## 关键原则

1. **Landing Page 优先于 App** - 先有页面，再上架
2. **文案 > 设计** - 说清楚"为什么要用你"比好看更重要
3. **SEO 从第一天开始** - 长尾流量需要时间积累
4. **用数据说话** - 不要靠感觉，看转化率

---

Created: $(date '+%Y-%m-%d')
