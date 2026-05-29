---
name: drawio-generator
description: 生成符合 IMA 项目规范的 Draw.io 图表（.drawio 文件）。当用户请求创建架构图、流程图、对比图、PPT 配图时，应使用此 Skill。支持自动应用配色规范、尺寸规范，并生成可直接用于 PPT 的专业图表。
---

# Draw.io 图表生成器

## 概述

此 Skill 用于生成符合 IMA 项目规范的 Draw.io 图表文件（`.drawio`），确保图表风格统一、专业，可直接用于 PPT 答辩和技术分享。

## 触发条件

当用户请求以下内容时触发此 Skill：

### 创建图表
- "帮我画一个架构图"
- "生成流程图"
- "画一个对比图"
- "生成 PPT 配图"
- "创建 drawio 图表"
- 任何涉及图表、架构图、流程图的请求

### 导出图表
- "导出 drawio"
- "把 xxx 导出成 SVG/PNG"
- "帮我导出图表"
- "转换 drawio 为 SVG"
- 任何涉及 drawio 文件导出的请求

## 核心规范

### 1. 尺寸规范

| 用途 | 推荐尺寸 | 比例 | 说明 |
|------|---------|------|------|
| **PPT 单页图** | `920 x 460` | 2:1 | 标准 PPT 页面图 |
| **PPT 单页图（大）** | `1120 x 640` | ~1.75:1 | 内容较多时使用 |
| **PPT 高清图** | `1840 x 920` | 2:1 | 高清导出用 |
| **PPT 半页图** | `920 x 230` | 4:1 | 横幅式展示 |

### 2. 简洁配色方案（3 色）

| 区块类型 | 背景色 | 边框色 | 文字色 | 用途 |
|---------|--------|--------|--------|------|
| **白色区** | `#FFFFFF` | `#E7E7E7` | `#242424` | 普通内容、代码框、流程步骤 |
| **浅蓝区** | `#F2F6FC` | `#0052D9` | `#242424` | 核心问题、关键发现、重点强调 |
| **深蓝栏** | `#0052D9` | `#0052D9` | `#FFFFFF` | 结论框、总结栏、最终方案 |

### 3. 对比图专用配色

| 区块类型 | 背景色 | 边框色 | 文字色 | 用途 |
|---------|--------|--------|--------|------|
| **错误/问题（❌）** | `#FFCDD2` | `#D32F2F` | `#424242` | 问题方案、错误示例 |
| **正确/优势（✅）** | `#C8E6C9` | `#388E3C` | `#424242` | 推荐方案、正确示例 |
| **VS 标签** | `#E8DEF8` | - | `#7B1FA2` | 对比分隔标签 |

## 图表生成流程

### Step 1: 确定图表类型和尺寸

根据用户需求选择：
- **架构图**：展示系统组件和关系
- **流程图**：展示步骤和流程
- **对比图**：左右对比两种方案
- **时序图**：展示时间顺序的交互

### Step 2: 设计布局

常见布局模式：
```
├── 三列并排：每列约 280px，间距 40px
├── 左右对比：每侧约 420px，间距 40px（带 VS 分隔线）
├── 上下结构：标题区 60px + 内容区 360px + 底部 40px
└── 四象限：每象限约 420x210
```

### Step 3: 生成 .drawio 文件

使用 XML 格式生成 Draw.io 文件，参考 `references/drawio-xml-reference.md` 获取完整的 XML 结构和样式模板。

## XML 样式速查

### 圆角设置（重要！）

**PPT 兼容性**：为确保导出 SVG 后在 PPT 中转换为形状时保留圆角效果，使用 `arcSize=12` 或更大值：

| arcSize 值 | 效果 | PPT 兼容性 |
|-----------|------|-----------|
| `arcSize=4` | 小圆角 | ❌ 转换后几乎看不到 |
| `arcSize=12` | 中等圆角 | ✅ 推荐，转换后可见 |
| `arcSize=20` | 大圆角 | ✅ 明显圆角 |

### 基础样式

```xml
<!-- 白色区（普通内容）- arcSize=12 确保 PPT 圆角可见 -->
style="rounded=1;arcSize=12;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#E7E7E7;strokeWidth=1;dashed=1;fontColor=#242424;"

<!-- 浅蓝区（重点强调） -->
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F2F6FC;strokeColor=#0052D9;strokeWidth=2;dashed=1;fontColor=#242424;"

<!-- 深蓝栏（结论总结） -->
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#0052D9;strokeColor=#0052D9;strokeWidth=2;fontColor=#FFFFFF;fontStyle=1;"
```

### 对比图样式

```xml
<!-- 错误方案（红色） -->
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#FFCDD2;strokeColor=#D32F2F;fontColor=#424242;dashed=1;strokeWidth=1;"

<!-- 正确方案（绿色） -->
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#C8E6C9;strokeColor=#388E3C;fontColor=#424242;dashed=1;strokeWidth=1;"

<!-- VS 标签 -->
style="text;html=1;strokeColor=none;fillColor=#E8DEF8;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=1;fontSize=14;fontStyle=1;fontColor=#7B1FA2;"
```

### 连接线样式

```xml
<!-- 箭头连接线 -->
style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#424242;strokeWidth=1;endArrow=classic;endFill=1;"

<!-- 分隔线（水平） -->
style="line;strokeWidth=2;html=1;strokeColor=#E7E7E7;"

<!-- 分隔线（垂直） -->
style="line;strokeWidth=2;html=1;strokeColor=#E7E7E7;direction=south;"
```

### 文字样式

```xml
<!-- 标题文字 -->
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#242424;"

<!-- 小节标题（红色强调） -->
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#D32F2F;"

<!-- 小节标题（绿色强调） -->
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#388E3C;"
```

## 文件模板

### 基础 .drawio 文件结构

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="Electron" version="29.0.3">
  <diagram name="第 1 页" id="unique-id">
    <mxGraphModel dx="1120" dy="640" grid="0" gridSize="10" guides="0" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- 在此添加图形元素 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## 导出功能

### ⚠️ 重要：自动导出指令

**生成 `.drawio` 文件后，必须立即执行导出命令：**

```bash
# 默认导出为 SVG（PPT 可编辑）
/Applications/draw.io.app/Contents/MacOS/draw.io --export --format svg --output "<输出路径>.svg" "<输入文件>.drawio"
```

**导出规则：**
1. **默认格式**：SVG（除非用户指定其他格式）
2. **输出位置**：与 `.drawio` 文件相同目录
3. **文件名**：与 `.drawio` 文件相同，仅扩展名不同

### 导出命令模板

```bash
# SVG（推荐，PPT 可编辑）
/Applications/draw.io.app/Contents/MacOS/draw.io --export --format svg --output "文件名.svg" "文件名.drawio"

# PNG（通用）
/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png --output "文件名.png" "文件名.drawio"

# PDF
/Applications/draw.io.app/Contents/MacOS/draw.io --export --format pdf --output "文件名.pdf" "文件名.drawio"
```

### 使用 Skill 脚本导出

也可以使用 Skill 自带的脚本：

```bash
# 导出为 SVG
/Users/voidzhang/Documents/workspace/t_chrome_dev/.codebuddy/skills/drawio-generator/scripts/export_drawio.sh "<file.drawio>" svg

# 导出为 PNG
/Users/voidzhang/Documents/workspace/t_chrome_dev/.codebuddy/skills/drawio-generator/scripts/export_drawio.sh "<file.drawio>" png
```

### 手动导出

在 Draw.io 应用中：

1. **导出为 SVG**（推荐，PPT 可编辑）
   - File → Export as → SVG
   - 勾选 Embed Images、Embed Fonts
   - PPT 中右键 → 转换为形状 → 可编辑

2. **导出为 PNG**（通用）
   - File → Export as → PNG
   - Zoom: 200%（高清）
   - 背景: 透明或白色

3. **导出为 EMF**（Windows 推荐）
   - File → Export as → Advanced → EMF
   - PPT 中可直接编辑

### 导出后在 PPT 中编辑 SVG

1. 插入 SVG 文件
2. 右键 → **转换为形状**（Convert to Shape）
3. 再次右键 → **取消组合**（Ungroup）
4. 现在可以编辑每个元素

## 注意事项

1. **ID 唯一性**：每个 mxCell 的 id 必须唯一
2. **坐标系统**：Draw.io 使用左上角为原点，y 轴向下为正
3. **HTML 转义**：value 中的 `<`、`>`、`&` 需要转义为 `&lt;`、`&gt;`、`&amp;`
4. **字体**：推荐使用系统默认字体，代码块使用 `Courier New`
5. **边距**：内容区域建议留 20-40px 边距
