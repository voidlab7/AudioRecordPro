#!/bin/bash
# INFRA-006: UI 自验 lite 通道（外部驱动端）
# 原理：写触发器 → 拉 App → App 内自动跑「录音→进编辑器→split/delete/undo/redo + AX 枚举」
#       → 每步吐 UXEventLog("UITest", step) → 本脚本轮询日志断言。
#       绕开 XCUITest Runner 的系统拉起链路（LOOP-05 卡点），无人值守可用。
#
# 用法: bash scripts/test-ui-lite.sh [app 路径，默认仓库 build/Loocap.app]
# 通过判据: 新增 UXEvents 中出现 UITest/done 且 ok=true（11 步全过：
#   baseline/baseline_hash/split/delete/undo/redo/draft_saved/original_untouched/draft_render/ax_enumerate/seek_align，
#   FEAT-007 草稿三断言 + UI-037 seek_align 合并态合计）
# 依赖: python3 / afplay
# INFRA-009: 声源改版——原 440Hz 正弦蜂鸣（刺耳）核对断言链后确认无判定作用：
#   baseline 仅断言 frameLength>0，split/delete/undo/redo 全命令级帧断言，
#   FIX-007「首帧 peak=」是一次性日志打点、无人消费数值；BUG-1 的 0 秒文件
#   由 frames/duration 断言拦截，与有无声源无关。
#   R2（老板 10-26 修订「删除蜂鸣用例，换播放一首歌」）：声源换为本地歌曲——
#   查找顺序 $LOOCAP_TEST_MUSIC → 婚礼音乐目录 → Downloads 最新 mp3/m4a →
#   回退生成 C 大调分解和弦琶音（柔和不刺耳）。lite 结束时 kill 播放。
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$REPO/build/Loocap.app}"
REC_DIR="$HOME/Library/Containers/com.microlab.loocap/Data/Documents/AudioRecordings"
LOG_DIR="$REC_DIR/Logs/UXEvents"
TRIGGER="$REC_DIR/selftest-record.txt"
SECS=10
ARPEG=/tmp/loocap_lite_arpeggio.wav

[ -d "$APP" ] || { echo "FAIL: App 不存在: $APP"; exit 1; }
[ -d "$LOG_DIR" ] || { echo "FAIL: UXEvents 目录不存在（先跑一次 App）: $LOG_DIR"; exit 1; }

# 测试声源：一首歌（INFRA-009 R2），找不到回退柔和琶音
MUSIC="${LOOCAP_TEST_MUSIC:-$HOME/Downloads/婚礼音乐/A Thousand Years - Christina Perri.mp3}"
if [ ! -f "$MUSIC" ]; then
  MUSIC=$(find "$HOME/Downloads" -maxdepth 2 -type f \( -name "*.mp3" -o -name "*.m4a" \) 2>/dev/null | sort | tail -1)
fi
if [ -n "$MUSIC" ] && [ -f "$MUSIC" ]; then
  SRC_DESC="歌: $(basename "$MUSIC")"
else
  MUSIC="$ARPEG"
  if [ ! -f "$ARPEG" ]; then
    python3 -c "
import wave, math, struct
sr = 44100
notes = [261.63, 329.63, 392.0, 523.25]  # C4 E4 G4 C5 分解和弦
seg = int(sr * 0.375)
f = wave.open('$ARPEG', 'w')
f.setnchannels(2); f.setsampwidth(2); f.setframerate(sr)
for rep in range(int(20 * sr / (seg * 4))):
    for hz in notes:
        for i in range(seg):
            env = math.sin(math.pi * i / seg)  # 每音淡入淡出包络
            v = int(6000 * env * math.sin(2 * math.pi * hz * i / sr))
            f.writeframes(struct.pack('<hh', v, v))
f.close()
"
  fi
  SRC_DESC="回退琶音: $ARPEG"
fi

# 起点快照（最新日志文件 + 行数），只认其后新增的 UITest 事件
BEFORE_FILE=$(ls "$LOG_DIR"/uxevents_*.jsonl 2>/dev/null | sort | tail -1)
BEFORE_LINES=0
[ -n "$BEFORE_FILE" ] && BEFORE_LINES=$(wc -l < "$BEFORE_FILE" | tr -d ' ')

pkill -x Loocap 2>/dev/null
pkill -x afplay 2>/dev/null
sleep 1
printf '10 mix uitest' > "$TRIGGER"
open "$APP"
(afplay "$MUSIC" &) 2>/dev/null
echo "测试声源 → $SRC_DESC"
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

# FEAT-007 第二段：草稿恢复端到端（退出编辑器→重进→帧数一致），等 UITest2.done（最长 45s）
deadline2 = time.time() + 45
events2 = []
while time.time() < deadline2:
    scan()
    events2 = [e for e in events if str(e.get("event", "")).startswith("UITest2")]
    if [e for e in events2 if e.get("event") == "UITest2.done"]:
        break
    time.sleep(2)

print("== UITest2 草稿恢复段 ==")
done2 = [e for e in events2 if e.get("event") == "UITest2.done"]
if not done2:
    print("FAIL: 45s 内未等到 UITest2/done（草稿恢复段未跑或超时）")
    ok = False
else:
    for e in events2:
        if e.get("event") == "UITest2.done":
            continue
        d = e.get("detail") or {}
        print(f'  {"PASS" if d.get("ok") else "FAIL"}  {e.get("event"):20s} {json.dumps(d, ensure_ascii=False)[:140]}')
    ok2 = (done2[-1].get("detail") or {}).get("ok") is True
    print(f'== UITest2 done: detail={json.dumps(done2[-1].get("detail", {}), ensure_ascii=False)} ==')
    ok = ok and ok2

print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
EOF
RC=$?
pkill -x Loocap 2>/dev/null
pkill -x afplay 2>/dev/null  # INFRA-009 R2: 收尾停歌（长歌不外溢）
exit $RC
