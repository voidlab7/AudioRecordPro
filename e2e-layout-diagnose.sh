#!/bin/bash
# AudioRecord e2e 布局诊断脚本
# 流程：点文件 Tab → 选第一个音频 → 切回录制 Tab → 截图前后对比
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/build/AudioRecordMac.app"
LOG_FILE="/tmp/audiorecord_e2e_$(date +%Y%m%d_%H%M%S).log"
SCREENSHOT_BEFORE="/tmp/audiorecord_before.png"
SCREENSHOT_AFTER="/tmp/audiorecord_after.png"

echo "🔨 [1/4] 编译..."
cd "$ROOT_DIR"
rm -rf build
bash build-app.sh >/dev/null 2>&1 || {
    echo "❌ 编译失败，查看 build-app.sh 输出"
    exit 1
}

echo "📋 [2/4] 启动日志捕获（log stream）..."
# 用 log stream 捕获 NSLog 输出
log stream --predicate 'eventMessage CONTAINS "LAYOUT-DEBUG"' --level=info > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 1

echo "🚀 [3/4] 启动 App..."
open "$APP_PATH"
sleep 2

# 截取"录制"态
screencapture -x -o -l $(osascript -e 'tell application "AudioRecordMac" to id of window 1' 2>/dev/null || echo "") "$SCREENSHOT_BEFORE" 2>/dev/null || screencapture -x "$SCREENSHOT_BEFORE"
echo "📸 before: $SCREENSHOT_BEFORE"

echo ""
echo "🖱 [4/4] 模拟用户操作（osascript）..."
osascript <<'EOF' 2>&1 | head -20
tell application "AudioRecordMac" to activate
delay 0.5

tell application "System Events"
    tell process "AudioRecordMac"
        -- 点击 "文件" Tab
        try
            click button "文件" of window 1
            delay 0.5
        end try

        -- 选第一个文件
        try
            click row 1 of outline 1 of scroll view 1 of window 1
            delay 0.5
        on error
            -- 备选: 点击第一个列表项
            try
                click item 1 of list 1 of window 1
                delay 0.5
            end try
        end try

        -- 切回 "录制" Tab
        try
            click button "录制" of window 1
            delay 1
        end try
    end tell
end tell
EOF

# 截取切回后的状态
screencapture -x "$SCREENSHOT_AFTER"
echo "📸 after:  $SCREENSHOT_AFTER"

echo ""
echo "🛑 停止日志捕获..."
kill $LOG_PID 2>/dev/null || true
sleep 1

echo ""
echo "============================================================"
echo "📋 LAYOUT-DEBUG 日志（关键路径）"
echo "============================================================"
grep "LAYOUT-DEBUG" "$LOG_FILE" | head -100 || echo "（暂无日志，可能未触发状态切换）"
echo ""
echo "完整日志: $LOG_FILE"
echo "对比截图: $SCREENSHOT_BEFORE  →  $SCREENSHOT_AFTER"
