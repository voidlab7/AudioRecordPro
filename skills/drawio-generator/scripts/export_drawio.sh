#!/bin/bash
# Draw.io 导出脚本
# 用法: ./export_drawio.sh <input.drawio> [format] [output_dir]
# format: svg (默认), png, pdf, emf
# 示例: ./export_drawio.sh diagram.drawio svg ./output

set -e

INPUT_FILE="$1"
FORMAT="${2:-svg}"
OUTPUT_DIR="${3:-.}"

if [ -z "$INPUT_FILE" ]; then
    echo "用法: $0 <input.drawio> [format] [output_dir]"
    echo "format: svg (默认), png, pdf"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "错误: 文件不存在: $INPUT_FILE"
    exit 1
fi

# 获取文件名（不含扩展名）
BASENAME=$(basename "$INPUT_FILE" .drawio)
OUTPUT_FILE="$OUTPUT_DIR/$BASENAME.$FORMAT"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# macOS Draw.io 路径
DRAWIO_APP="/Applications/draw.io.app/Contents/MacOS/draw.io"

if [ ! -f "$DRAWIO_APP" ]; then
    echo "错误: Draw.io 未安装，请运行: brew install --cask drawio"
    exit 1
fi

echo "导出: $INPUT_FILE -> $OUTPUT_FILE"
"$DRAWIO_APP" --export --format "$FORMAT" --output "$OUTPUT_FILE" "$INPUT_FILE"

echo "✅ 导出成功: $OUTPUT_FILE"
