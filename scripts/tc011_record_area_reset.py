#!/usr/bin/env python3
"""TC-011 回归驱动：录制区切换状态重置（可观测性回放断言，不依赖截图/VLM）。

场景：文件列表进编辑器 → 点「录制」Tab 切回 → 断言录制区被重置。

断言（UXEvents JSONL 事件序列，全部基于 epoch_ms 过滤本次注入产生的事件）：
  enter_editor → editor_shown → tab_changed(audioRecorder) → record_area_reset
FAIL 条件：切回录制 Tab 后未出现 record_area_reset（即残留旧状态）。

用法:
  python3 scripts/tc011_record_area_reset.py            # 全流程（默认驱动 build/AudioRecordMac.app）
  python3 scripts/tc011_record_area_reset.py --no-relaunch  # 不重启 App（App 已带修复版本在跑）
"""
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent
ART_DIR = PROJ / "e2e" / "artifacts" / f"TC-011-{datetime.now().strftime('%Y%m%d')}"
UXEVENTS_DIR = Path.home() / "Library/Containers/com.microlab.loocap/"
UXEVENTS_DIR /= "Data/Documents/AudioRecordings/Logs/UXEvents"

# 窗口内坐标（AppKit 底左原点，窗口固定 1200x750）
POS_FILE_TAB = (171, 692)
POS_RECORD_TAB = (61, 692)
POS_FIRST_ROW = (136, 632)
ROW_FALLBACK_YS = [632, 620, 644, 608, 656]

osascript = lambda s: subprocess.run(
    ["osascript", "-e", s], capture_output=True, text=True
)

# CGEvent 注入：落点精确 + 会被 App 的 input 层监控捕获（双通道证据）
import Quartz  # noqa: E402


def cg_click_screen(sx: int, sy: int) -> None:
    pt = (sx, sy)
    move = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, pt, Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, move)
    time.sleep(0.05)
    for t in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
        e = Quartz.CGEventCreateMouseEvent(None, t, pt, Quartz.kCGMouseButtonLeft)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
        time.sleep(0.05)


def latest_jsonl() -> Path | None:
    files = sorted(UXEVENTS_DIR.glob("uxevents_*.jsonl"))
    return files[-1] if files else None


def read_events(path: Path, since_ms: int) -> list[dict]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("epoch_ms", 0) > since_ms:
            out.append(e)
    return out


def window_geometry() -> tuple[int, int, int, int]:
    r = osascript(
        'tell application "System Events" to tell process "AudioRecordMac"'
        " to get {position, size} of window 1"
    ).stdout.strip()
    wx, wy, ww, wh = [int(v) for v in r.replace(" ", "").split(",")]
    return wx, wy, ww, wh


def click_at_window(xw: int, yw: int) -> None:
    wx, wy, ww, wh = window_geometry()
    sx, sy = wx + xw, wy + (wh - yw)  # 底左原点 → 屏幕顶左原点
    cg_click_screen(sx, sy)


def app_window_id() -> int | None:
    """后台拿 AudioRecordMac 主窗口的 CGWindowID（不抢前台、不切屏）。"""
    infos = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID)
    for info in infos:
        if info.get(Quartz.kCGWindowOwnerName) == "AudioRecordMac" and info.get(Quartz.kCGWindowLayer, 0) == 0:
            return int(info[Quartz.kCGWindowNumber])
    return None


def screenshot(name: str) -> Path:
    """只截 App 窗口（screencapture -l），窗口在后台/被遮挡也能截。"""
    out = ART_DIR / name
    wid = app_window_id()
    if wid is None:
        print(f"WARN: 找不到 AudioRecordMac 窗口，跳过截图 {name}")
        return out
    # -o 不带窗口阴影，产出即窗口本体（1200x750 @2x = 2400x1500）
    subprocess.run(["screencapture", "-x", "-o", "-l", str(wid), str(out)], capture_output=True)
    return out


def wait_for(events_src, since_ms, pred, timeout=8.0):
    """轮询 JSONL 直到出现满足 pred 的事件，返回该事件或 None。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for e in read_events(events_src(), since_ms):
            if pred(e):
                return e
        time.sleep(0.25)
    return None


def brief(e: dict) -> str:
    d = e.get("detail", {}) or {}
    return f"{e.get('ts','')} [{e.get('type')}] {e.get('event')} {json.dumps({k:v for k,v in d.items() if k!='view_tree'}, ensure_ascii=False)}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-relaunch", action="store_true")
    args = ap.parse_args()
    ART_DIR.mkdir(parents=True, exist_ok=True)
    lines: list[str] = ["# TC-011 执行记录", ""]

    if not args.no_relaunch:
        print("== 重启 App（加载修复版本）==")
        osascript('tell application "AudioRecordMac" to quit')
        time.sleep(1.5)
        subprocess.run(["open", str(PROJ / "build/AudioRecordMac.app")], check=True)
        time.sleep(3.0)

    app_launch_ms = int(time.time() * 1000)
    src = latest_jsonl()
    if src is None:
        print("FAIL: 找不到 UXEvents 文件", file=sys.stderr)
        return 2
    print(f"事件文件: {src.name}")

    # Step1: 文件 Tab
    click_at_window(*POS_FILE_TAB)
    ev_tab_files = wait_for(
        lambda: latest_jsonl(), app_launch_ms,
        lambda e: e.get("event") == "tab_changed" and e.get("detail", {}).get("tab") == "recordedFiles")
    print(f"[1] tab_changed=recordedFiles: {'OK' if ev_tab_files else 'MISS'}")

    # Step2: 点第一行文件 → editor_shown
    ev_editor = None
    for y in ROW_FALLBACK_YS:
        click_at_window(POS_FIRST_ROW[0], y)
        ev_editor = wait_for(
            lambda: latest_jsonl(), app_launch_ms,
            lambda e: e.get("event") == "editor_shown", timeout=3.0)
        if ev_editor:
            break
    print(f"[2] editor_shown: {'OK ' + brief(ev_editor) if ev_editor else 'MISS'}")
    shot_editor = screenshot("tc011-2-in-editor.png")

    # Step3: 切回录制 Tab
    click_at_window(*POS_RECORD_TAB)
    ev_tab_rec = wait_for(
        lambda: latest_jsonl(), app_launch_ms,
        lambda e: e.get("event") == "tab_changed" and e.get("detail", {}).get("tab") == "audioRecorder")
    print(f"[3] tab_changed=audioRecorder: {'OK' if ev_tab_rec else 'MISS'}")

    # Step4: 断言 record_area_reset（修复点证据）
    ev_reset = wait_for(
        lambda: latest_jsonl(), app_launch_ms,
        lambda e: e.get("event") == "record_area_reset", timeout=3.0)
    print(f"[4] record_area_reset: {'OK ' + brief(ev_reset) if ev_reset else 'MISS'}")
    shot_after = screenshot("tc011-3-after-back.png")

    seq_ok = ev_tab_files and ev_editor and ev_tab_rec and ev_reset
    verdict = "PASS" if seq_ok else "FAIL"
    lines += [
        f"- 事件文件: `{src.name}`",
        f"- tab_changed=recordedFiles: {'✅' if ev_tab_files else '❌'}",
        f"- editor_shown: {'✅' if ev_editor else '❌'}",
        f"- tab_changed=audioRecorder: {'✅' if ev_tab_rec else '❌'}",
        f"- record_area_reset: {'✅' if ev_reset else '❌'}",
        f"- 截图: {shot_editor.name} / {shot_after.name}",
        "",
        f"## 结论: **{verdict}**",
    ]
    report = ART_DIR / "report.md"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"报告: {report}")
    return 0 if seq_ok else 1


if __name__ == "__main__":
    sys.exit(main())
