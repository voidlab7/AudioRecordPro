# REQ-1.2-01 FFmpeg 静态库集成

> **版本**：V1.2 | **优先级**：P0 | **预估**：2天
> **状态**：⬜ 待开发
> **关联**：[需求列表](./README.md) | [V1_功能细化](../product/v1-feature-breakdown.md)

---

## 用户故事

> **作为**开发者，**我需要**集成 FFmpeg 静态库，**以便**支持 MP3/FLAC/OGG 等 AVFoundation 不原生支持的格式转换。

---

## 功能描述

将 FFmpeg 以静态库形式集成到项目中，确保 App Store 审核合规。

---

## 技术要求

1. 编译 FFmpeg 6.x 静态库
2. 仅包含需要的编解码器（MP3/FLAC/OGG/Vorbis）
3. License 合规（LGPL）
4. 不包含 GPL 组件
5. App Store 审核可通过

---

## 编解码器清单

| 编解码器 | 用途 |
|----------|------|
| libmp3lame | MP3 编码 |
| mp3 decoder | MP3 解码 |
| flac | FLAC 编解码 |
| libvorbis | OGG/Vorbis 编解码 |
| pcm_* | PCM 格式支持 |
| aac | AAC 编解码（备用） |

---

## 验收标准

| # | 标准 | 通过条件 |
|---|------|----------|
| 1 | 编译成功 | 静态库编译无错误 |
| 2 | 体积 | 静态库体积合理（< 20MB） |
| 3 | License | 不包含 GPL 组件，LGPL 合规 |
| 4 | 集成 | 项目可正常链接和调用 |
| 5 | 沙盒 | 在 App Sandbox 环境下正常工作 |

---

## 风险

- FFmpeg 在 Mac App Store 审核可能有问题
- 需提前调研审核案例
- 备选方案：使用 AVFoundation 覆盖尽可能多的格式

---

## 依赖

- Xcode Command Line Tools
- Homebrew（编译环境）
