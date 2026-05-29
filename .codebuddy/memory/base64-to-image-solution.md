# Base64 图片展示方案

> 当 MCP 工具返回 Base64 编码的图片（如登录二维码）时，聊天窗口无法直接渲染图片。
> 以下是将 Base64 转为可视图片的解决方案。

---

## 方案：生成 HTML 文件 + 浏览器打开

### 原理
将 Base64 数据嵌入 HTML 的 `<img>` 标签的 `data:` URI 中，用浏览器渲染。

### 步骤

1. **提取 Base64 数据**：从 MCP 返回的 JSON 中提取 `data` 字段和 `mimeType` 字段
2. **生成 HTML 文件**：创建包含 `<img src="data:{mimeType};base64,{data}">` 的 HTML
3. **用浏览器打开**：`open qrcode.html`（macOS）

### HTML 模板

```html
<!DOCTYPE html>
<html>
<head><title>二维码</title></head>
<body style="display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f5;flex-direction:column;">
  <h2>📱 请用小红书 App 扫码登录</h2>
  <img src="data:image/png;base64,{BASE64_DATA}" style="width:300px;height:300px;image-rendering:pixelated;">
  <p style="color:#999;margin-top:16px;">⏰ 有效期约 5 分钟，请尽快扫码</p>
</body>
</html>
```

### 自动化命令（macOS）

```bash
# 1. 生成 HTML 文件（将 BASE64_DATA 替换为实际数据）
cat > /tmp/qrcode.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>二维码</title></head>
<body style="display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f5;flex-direction:column;">
  <h2>📱 请扫码登录</h2>
  <img src="data:image/png;base64,{BASE64_DATA}" style="width:300px;height:300px;image-rendering:pixelated;">
</body>
</html>
EOF

# 2. 用默认浏览器打开
open /tmp/qrcode.html
```

### 备选方案

| 方案 | 命令 | 说明 |
|------|------|------|
| HTML + 浏览器 | `open qrcode.html` | ✅ 推荐，最简单 |
| base64 命令解码 | `echo "{data}" \| base64 -d > qrcode.png && open qrcode.png` | 直接解码为 PNG 文件 |
| Python 脚本 | `python3 -c "import base64; open('qr.png','wb').write(base64.b64decode('{data}'))"` | 适合自动化脚本 |

---

## 使用场景

- 小红书 MCP 的 `get_login_qrcode` 返回 Base64 二维码
- 任何 MCP 工具返回 Base64 编码的图片数据
- AI 对话窗口无法直接渲染图片时的通用解决方案

## 注意事项

- 二维码有有效期（通常 5 分钟），生成后需尽快扫码
- HTML 文件用完可删除，或放在 `/tmp/` 目录自动清理
- `image-rendering: pixelated` 样式可防止二维码被模糊缩放
