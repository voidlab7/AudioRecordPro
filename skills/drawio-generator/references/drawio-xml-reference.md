# Draw.io XML 完整参考

## 文件结构

### 完整文件模板

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="Electron" agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/29.0.3 Chrome/140.0.7339.249 Electron/38.7.0 Safari/537.36" version="29.0.3">
  <diagram name="第 1 页" id="page-id">
    <mxGraphModel dx="1120" dy="640" grid="0" gridSize="10" guides="0" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- 图形元素从 id="2" 开始 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

### mxGraphModel 属性说明

| 属性 | 说明 | 推荐值 |
|------|------|--------|
| `dx` | 画布宽度 | 920 / 1120 / 1840 |
| `dy` | 画布高度 | 460 / 640 / 920 |
| `grid` | 显示网格 | 0（关闭） |
| `gridSize` | 网格大小 | 10 |
| `guides` | 显示辅助线 | 0 |
| `page` | 显示页面边框 | 0（关闭） |

---

## 图形元素

### 矩形框

**重要**：使用 `arcSize=12` 确保 PPT 转换后圆角可见（`arcSize=4` 太小会丢失）

```xml
<!-- arcSize=12 确保 PPT 圆角可见 -->
<mxCell id="2" value="内容文字" style="rounded=1;arcSize=12;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#E7E7E7;strokeWidth=1;dashed=1;fontColor=#242424;fontSize=12;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="200" height="80" as="geometry" />
</mxCell>
```

### 文字标签

```xml
<mxCell id="3" value="标题文字" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#242424;" vertex="1" parent="1">
  <mxGeometry x="100" y="50" width="200" height="30" as="geometry" />
</mxCell>
```

### 连接线（箭头）

```xml
<mxCell id="4" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#424242;strokeWidth=1;endArrow=classic;endFill=1;" edge="1" source="2" target="5" parent="1">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
```

### 分隔线

```xml
<!-- 水平分隔线 -->
<mxCell id="5" value="" style="line;strokeWidth=2;html=1;strokeColor=#E7E7E7;" vertex="1" parent="1">
  <mxGeometry x="100" y="200" width="800" height="10" as="geometry" />
</mxCell>

<!-- 垂直分隔线 -->
<mxCell id="6" value="" style="line;strokeWidth=2;html=1;strokeColor=#E7E7E7;direction=south;" vertex="1" parent="1">
  <mxGeometry x="500" y="100" width="10" height="400" as="geometry" />
</mxCell>
```

---

## 完整样式库

### 1. 基础区块样式

#### 白色区（普通内容）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#E7E7E7;strokeWidth=1;dashed=1;fontColor=#242424;fontSize=12;verticalAlign=middle;"
```

#### 浅蓝区（重点强调）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F2F6FC;strokeColor=#0052D9;strokeWidth=2;dashed=1;fontColor=#242424;fontSize=12;verticalAlign=middle;"
```

#### 深蓝区（核心信息）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#D4E3FC;strokeColor=#0052D9;fontColor=#0052D9;fontSize=12;dashed=1;strokeWidth=1;verticalAlign=middle;"
```

#### 深蓝栏（结论总结）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#0052D9;strokeColor=#003DA5;fontColor=#FFFFFF;fontSize=12;fontStyle=1;dashed=1;strokeWidth=1;verticalAlign=middle;"
```

### 2. 对比图样式

#### 错误/问题方案（红色）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#FFCDD2;strokeColor=#D32F2F;fontColor=#424242;fontSize=10;dashed=1;strokeWidth=1;verticalAlign=middle;"
```

#### 正确/推荐方案（绿色）
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#C8E6C9;strokeColor=#388E3C;fontColor=#424242;fontSize=10;dashed=1;strokeWidth=1;verticalAlign=middle;"
```

#### 灰色说明框
```xml
style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F5F5F5;strokeColor=#9E9E9E;fontColor=#424242;fontSize=11;dashed=1;strokeWidth=1;verticalAlign=middle;"
```

#### VS 标签
```xml
style="text;html=1;strokeColor=none;fillColor=#E8DEF8;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=1;fontSize=14;fontStyle=1;fontColor=#7B1FA2;"
```

### 3. 文字样式

#### 主标题
```xml
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=20;fontStyle=1;fontColor=#242424;"
```

#### 小节标题
```xml
style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=14;fontStyle=1;fontColor=#424242;"
```

#### 错误标题（红色）
```xml
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#D32F2F;"
```

#### 正确标题（绿色）
```xml
style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;fontColor=#388E3C;"
```

### 4. 连接线样式

#### 正交箭头（推荐）
```xml
style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#424242;strokeWidth=1;endArrow=classic;endFill=1;"
```

#### 直线箭头
```xml
style="endArrow=classic;html=1;strokeColor=#424242;strokeWidth=1;"
```

#### 虚线箭头
```xml
style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#424242;strokeWidth=1;endArrow=classic;endFill=1;dashed=1;"
```

---

## 表格绘制

### HTML 表格（嵌入在 value 中）

```xml
<mxCell id="10" value="&lt;table style=&quot;font-size:10px;&quot;&gt;&lt;tr&gt;&lt;th&gt;维度&lt;/th&gt;&lt;th&gt;方案A&lt;/th&gt;&lt;th&gt;方案B&lt;/th&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td&gt;性能&lt;/td&gt;&lt;td&gt;&lt;font color=&quot;#D32F2F&quot;&gt;❌ 差&lt;/font&gt;&lt;/td&gt;&lt;td&gt;&lt;font color=&quot;#388E3C&quot;&gt;✅ 好&lt;/font&gt;&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;" style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F5F5F5;strokeColor=#9E9E9E;fontColor=#424242;fontSize=10;dashed=1;strokeWidth=1;verticalAlign=middle;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="200" height="100" as="geometry" />
</mxCell>
```

### 多行文本（使用 `<br>`）

```xml
<mxCell id="11" value="&lt;b&gt;标题&lt;/b&gt;&lt;br&gt;第一行内容&lt;br&gt;第二行内容&lt;br&gt;&lt;font color=&quot;#D32F2F&quot;&gt;红色警告&lt;/font&gt;" style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#E7E7E7;fontColor=#424242;fontSize=11;dashed=1;strokeWidth=1;verticalAlign=middle;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="200" height="80" as="geometry" />
</mxCell>
```

---

## 代码块样式

### 等宽字体代码框

```xml
<mxCell id="12" value="&lt;b&gt;代码示例&lt;/b&gt;&lt;br&gt;├── function1()&lt;br&gt;├── function2()&lt;br&gt;└── function3()" style="rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#E7E7E7;fontColor=#424242;fontSize=10;dashed=1;strokeWidth=1;verticalAlign=top;align=left;spacingLeft=10;spacingTop=5;fontFamily=Courier New;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="200" height="100" as="geometry" />
</mxCell>
```

---

## 常用 Emoji

| Emoji | 用途 | 示例 |
|-------|------|------|
| 📊 | 数据/图表 | 📊 核心表 |
| 💡 | 思路/想法 | 💡 思路 |
| ⚠️ | 警告/问题 | ⚠️ 致命问题 |
| ✅ | 正确/成功 | ✅ 推荐方案 |
| ❌ | 错误/失败 | ❌ 问题方案 |
| 🔴 | 红色标记 | 🔴 代码改动 |
| 🟢 | 绿色标记 | 🟢 优势 |
| 📌 | 结论/重点 | 📌 结论 |

---

## 坐标计算参考

### 左右对比布局（1120 x 640）

```
左侧区域：x = 20 ~ 540（宽度 520）
分隔线：x = 550
右侧区域：x = 560 ~ 1100（宽度 540）

顶部标题：y = 20 ~ 60
内容区域：y = 70 ~ 580
底部结论：y = 590 ~ 630
```

### 三列布局（920 x 460）

```
第一列：x = 20 ~ 290（宽度 270）
第二列：x = 310 ~ 580（宽度 270）
第三列：x = 600 ~ 870（宽度 270）
边距：20px
列间距：20px
```
