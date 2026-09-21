#!/usr/bin/env python3
"""UXEventLog 回放工具 — 把 JSONL 事件流还原成用户操作时间线。

用法:
  python3 scripts/ux_replay.py                     # 回放最新一次会话
  python3 scripts/ux_replay.py --file <uxevents_*.jsonl>
  python3 scripts/ux_replay.py --stats             # 只输出操作统计
  python3 scripts/ux_replay.py --type input,module # 只看指定类型
  python3 scripts/ux_replay.py --out timeline.md   # 落盘为 markdown

事件文件位置: 沙盒 ~/Library/Containers/com.voidzhang.audio-record-mac/Data/
  Documents/AudioRecordings/Logs/UXEvents/uxevents_*.jsonl
"""
import argparse
import glob
import json
import os
import sys
from collections import Counter

SANDBOX = os.path.expanduser(
    "~/Library/Containers/com.voidzhang.audio-record-mac/Data/"
    "Documents/AudioRecordings/Logs/UXEvents"
)

TYPE_ICON = {
    "lifecycle": "🚀",
    "input": "🖱",
    "action": "⚡",
    "state": "🔀",
    "module": "🧩",
    "artifact": "📦",
}


def latest_file():
    files = sorted(glob.glob(os.path.join(SANDBOX, "uxevents_*.jsonl")))
    if not files:
        sys.exit(f"未找到事件文件，目录: {SANDBOX}")
    return files[-1]


def describe_event(e):
    etype = e.get("type", "?")
    event = e.get("event", "?")
    d = e.get("detail", {}) or {}

    if etype == "input":
        target = d.get("target") or d.get("hit", "?")
        if event == "click":
            return f"CLICK  [{target}] button={d.get('button','left')} @ ({d.get('x')},{d.get('y')})"
        if event == "key":
            return f"KEY    [{target or '-'}] {d.get('modifiers','')} {d.get('key','?')!r}"
        if event == "scroll":
            return f"SCROLL [{target}] dy={d.get('deltaY')} dx={d.get('deltaX')}"
        return f"{event} {json.dumps(d, ensure_ascii=False)}"

    if etype == "module":
        parts = []
        if "ok" in d:
            parts.append(f"ok={d['ok']}")
        if "elapsed_ms" in d:
            parts.append(f"{d['elapsed_ms']}ms")
        extra = {k: v for k, v in d.items() if k not in ("module", "ok", "elapsed_ms")}
        if extra:
            parts.append(json.dumps(extra, ensure_ascii=False))
        return f"{event} " + " ".join(str(p) for p in parts) if parts else event

    if etype == "state":
        # 视图树快照太长，只留元信息
        slim = {k: v for k, v in d.items() if k != "view_tree"}
        tree_lines = d.get("view_tree", "")
        n_nodes = len(tree_lines.splitlines()) if tree_lines else 0
        return f"{event} {json.dumps(slim, ensure_ascii=False)} (tree={n_nodes} nodes)"

    if etype == "artifact":
        return f"{event} path={d.get('path','')} size={d.get('size','?')}"

    return f"{event} {json.dumps(d, ensure_ascii=False)[:200]}"


def main():
    ap = argparse.ArgumentParser(description="UXEventLog 回放工具")
    ap.add_argument("--file", help="指定 JSONL 文件，默认取最新")
    ap.add_argument("--stats", action="store_true", help="只输出操作统计")
    ap.add_argument("--type", default="", help="过滤事件类型，逗号分隔，如 input,module")
    ap.add_argument("--out", help="结果落盘为 markdown 文件")
    args = ap.parse_args()

    path = args.file or latest_file()
    only_types = {t.strip() for t in args.type.split(",") if t.strip()} if args.type else None

    events = []
    with open(path, encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"⚠️ 第 {line_no} 行解析失败: {line[:80]}", file=sys.stderr)

    if only_types:
        events = [e for e in events if e.get("type") in only_types]

    out_lines = [f"# UX 事件回放: {os.path.basename(path)}", ""]
    out_lines.append(f"- 会话: {events[0].get('session') if events else '?'}")
    out_lines.append(f"- 事件数: {len(events)}")
    out_lines.append("")

    if args.stats:
        clicks = Counter()
        modules = Counter()
        for e in events:
            d = e.get("detail", {}) or {}
            if e.get("type") == "input" and e.get("event") == "click":
                clicks[d.get("target") or d.get("hit", "?")] += 1
            if e.get("type") == "module":
                status = "FAIL" if d.get("ok") is False else "ok"
                modules[f"{e.get('event')} [{status}]"] += 1
        out_lines.append("## 点击统计")
        for name, n in clicks.most_common():
            out_lines.append(f"- {name}: {n} 次")
        out_lines.append("")
        out_lines.append("## 模块调用统计")
        for name, n in modules.most_common():
            out_lines.append(f"- {name}: {n} 次")
    else:
        out_lines.append("## 时间线")
        prev_epoch = None
        for e in events:
            ts = e.get("ts", "")
            short_ts = ts.split(" ", 1)[-1] if " " in ts else ts
            gap = ""
            if prev_epoch is not None and e.get("epoch_ms"):
                delta = e["epoch_ms"] - prev_epoch
                if delta > 5000:
                    gap = f" ⏸ +{delta // 1000}s"
            prev_epoch = e.get("epoch_ms", prev_epoch)
            icon = TYPE_ICON.get(e.get("type"), "·")
            out_lines.append(f"- `{short_ts}` {icon} {describe_event(e)}{gap}")

    report = "\n".join(out_lines)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(report + "\n")
        print(f"已写入 {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
