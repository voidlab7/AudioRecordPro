#!/bin/bash
# INFRA-006: UI 自验 lite 通道（外部驱动端）
# 原理：写触发器 → 拉 App → App 内自动跑「录音→进编辑器→split/delete/undo/redo + AX 枚举」
#       → 每步吐 UXEventLog("UITest", step) → 本脚本轮询日志断言。
#       绕开 XCUITest Runner 的系统拉起链路（LOOP-05 卡点），无人值守可用。
#
# 用法: bash scripts/test-ui-lite.sh [app 路径，默认仓库 build/Loocap.app]
# 通过判据: 新增 UXEvents 中出现 UITest/done 且 ok=true（6 步全过）
# 依赖: python3 / afplay（测试音防御 BUG-1 静音拦截）
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$REPO/build/Loocap.app}"
REC_DIR="$HOME/Library/Containers/com.microlab.loocap/Data/Documents/AudioRecordings"
LOG_DIR="$REC_DIR/Logs/UXEvents"
TRIGGER="$REC_DIR/selftest-record.txt"
TONE=/tmp/loocap_lite_tone.wav
SECS=10

[ -d "$APP" ] || { echo "FAIL: App 不存在: $APP"; exit 1; }
[ -d "$LOG_DIR" ] || { echo "FAIL: UXEvents 目录不存在（先跑一次 App）: $LOG_DIR"; exit 1; }

# 测试音：无则生成 20s 440Hz（覆盖 3s 延迟 + 10s 录音窗）
if [ ! -f "$TONE" ]; then
  python3 -c "
import wave, math, struct
f = wave.open('$TONE', 'w')
f.setnchannels(2); f.setsampwidth(2); f.setframerate(44100)
for i in range(44100*20):
    v = int(12000*math.sin(2*math.pi*440*i/44100))
    f.writeframes(struct.pack('<hh', v, v))
f.close()
"
  echo "已生成测试音: $TONE"
fi

# 起点快照（最新日志文件 + 行数），只认其后新增的 UITest 事件
BEFORE_FILE=$(ls "$LOG_DIR"/uxevents_*.jsonl 2>/dev/null | sort | tail -1)
BEFORE_LINES=0
[ -n "$BEFORE_FILE" ] && BEFORE_LINES=$(wc -l < "$BEFORE_FILE" | tr -d ' ')

pkill -x Loocap 2>/dev/null
sleep 1
printf '10 mix uitest' > "$TRIGGER"
open "$APP"
(afplay "$TONE" &) 2>/dev/null
echo "已触发（10s mix uitest），轮询 UITest 事件（最长 150s）..."

python3 - "$LOG_DIR" "$BEFORE_FILE" "$BEFORE_LINES" <<'EOF'
import glob, json, os, sys, time

log_dir, before_file, before_lines = sys.argv[1], sys.argv[2], int(sys.argv[3])
deadline = time.time() + 150
events = []

def scan():
    """收集起点之后的新增行中的 UITest 事件"""
    files = sorted(glob.glob(os.path.join(log_dir, "uxevents_*.jsonl")))
    for path in files:
        skip = before_lines if os.path.realpath(path) == os.path.realpath(before_file) else 0
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f):
                    if i < skip:
                        continue
                    try:
                        e = json.loads(line)
                    except Exception:
                        continue
                    # UXEventLog jsonl: 顶层 event 形如 "UITest.baseline"（module 在 detail 内）
                    if str(e.get("event", "")).startswith("UITest"):
                        key = (path, i)
                        if key not in seen:
                            seen.add(key)
                            events.append(e)
        except OSError:
            pass

seen = set()
while time.time() < deadline:
    scan()
    done = [e for e in events if e.get("event") == "UITest.done"]
    if done:
        break
    time.sleep(2)

done = [e for e in events if e.get("event") == "UITest.done"]
print()
if not done:
    got = [f'{e.get("event")}(ok={e.get("ok")})' for e in events]
    print(f"FAIL: 150s 内未等到 UITest/done。已见 {len(events)} 条: {got}")
    sys.exit(1)

ok = (done[-1].get("detail") or {}).get("ok") is True
print("== UITest 步骤结果 ==")
for e in events:
    if e.get("event") == "UITest.done":
        continue
    d = e.get("detail") or {}
    detail = json.dumps(d, ensure_ascii=False)
    print(f'  {"PASS" if d.get("ok") else "FAIL"}  {e.get("event"):20s} {detail[:140]}')
print(f'== done: detail={json.dumps(done[-1].get("detail", {}), ensure_ascii=False)} ==')
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
EOF
RC=$?
pkill -x Loocap 2>/dev/null
exit $RC
