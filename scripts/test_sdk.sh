#!/bin/bash
set -euo pipefail

# AudioRecord SDK 测试脚本
# 使用 SwiftPM (swift test) 运行 AudioRecordKit 单元测试

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="$ROOT_DIR/AudioRecordKit"

# 解析命令行参数
VERBOSE=false
FILTER=""
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -b|--basic)
            # 保持向后兼容：--basic 等同于默认行为
            shift
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            HELP=true
            shift
            ;;
    esac
done

# 显示帮助信息
if [ "$HELP" = true ]; then
    echo "AudioRecord SDK 测试脚本 (SwiftPM)"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -b, --basic      运行所有单元测试（默认）"
    echo "  -v, --verbose    显示详细输出"
    echo "  -f, --filter X   只运行包含 X 的测试"
    echo "  -h, --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                        # 运行全部测试"
    echo "  $0 --verbose              # 详细输出"
    echo "  $0 --filter AudioUtils    # 只跑 AudioUtils 相关测试"
    exit 0
fi

echo "🧪 AudioRecord SDK 测试 (SwiftPM)"
echo "================================"

if [ ! -f "$SDK_DIR/Package.swift" ]; then
    echo "❌ Package.swift 未找到: $SDK_DIR"
    exit 1
fi

# 构建测试命令
CMD="swift test"
if [ "$VERBOSE" = true ]; then
    CMD="$CMD --verbose"
fi
if [ -n "$FILTER" ]; then
    CMD="$CMD --filter $FILTER"
fi

echo "📦 Package: $SDK_DIR"
echo "📋 命令: $CMD"
echo "================================"

# 运行测试
cd "$SDK_DIR"
eval "$CMD"
EXIT_CODE=$?

echo "================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ SDK 测试全部通过"
else
    echo "❌ SDK 测试有失败项 (exit code: $EXIT_CODE)"
fi
exit $EXIT_CODE
