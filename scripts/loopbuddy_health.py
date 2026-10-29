#!/usr/bin/env python3
"""LoopBuddy 健康体检（只读）。

监控哲学：LoopBuddy 没有常驻进程，「进程活着」这个指标毫无意义。
真正要监控的是四件事，且第一件最重要：

  1. 心跳   —— 最近一轮战报有多新（**缺一次比错一次更危险**）
  2. 自洽   —— 战报声称的 PASS，在原始证据里是否成立（防自我合理化）
  3. 代谢   —— 池子是否在流动（doing 卡死 / rfr 积压 / 无单可拉）
  4. 完整性 —— master 是否被越权改动（loop 只走 worktree + 验收后合并）

退出码：0=健康  1=有警告  2=有失败（应立刻看）

用法：
  python3 scripts/loopbuddy_health.py            # 人读
  python3 scripts/loopbuddy_health.py --json     # 机器读（给晨报/自动化）
"""
import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TODOS = ROOT / "TODOS.md"
REPORTS = ROOT / "docs" / "LoopBuddy"
LOGS = ROOT / "test_logs"

# 阈值（小时）。手动触发期的宽阈值；挂上每日定时后改成 26 / 50。
HEARTBEAT_WARN_H = 48.0
HEARTBEAT_FAIL_H = 96.0
DOING_WARN_H = 12.0
RFR_WARN_H = 48.0

ICON = {"ok": "✅", "warn": "⚠️ ", "fail": "⛔"}


def sh(args):
    try:
        r = subprocess.run(args, cwd=str(ROOT), capture_output=True, text=True, timeout=30)
        return r.stdout.strip()
    except Exception:
        return ""


def hours_ago(ts):
    return (time.time() - ts) / 3600.0


def check_heartbeat(reports):
    if not reports:
        return dict(id="heartbeat", level="fail", title="心跳",
                    detail="docs/LoopBuddy/ 下没有任何 R*-*.md 战报 —— 循环从未跑过或产物被删",
                    value=None)
    last = reports[-1]
    h = hours_ago(last.stat().st_mtime)
    age = f"{h:.1f}h 前"
    if h > HEARTBEAT_FAIL_H:
        lv, note = "fail", f"超过 {HEARTBEAT_FAIL_H:.0f}h 无轮次，循环实质已停"
    elif h > HEARTBEAT_WARN_H:
        lv, note = "warn", f"超过 {HEARTBEAT_WARN_H:.0f}h 无轮次，检查触发器是否还在"
    else:
        lv, note = "ok", "心跳正常"
    return dict(id="heartbeat", level=lv, title="心跳",
                detail=f"最近一轮 {last.name}（{age}）· {note}",
                value=round(h, 1))


def parse_report_sources(text):
    """从战报的『观察结果』表提取各信号源声明。"""
    rows = []
    for line in text.splitlines():
        m = re.match(r"^\|\s*[①②③④⑤⑥⑦]\s*\|([^|]*)\|([^|]*)\|([^|]*)\|", line)
        if not m:
            continue
        name, status, evid = (x.strip() for x in m.groups())
        state = "pass" if "✅" in status else ("blocked" if "⛔" in status else
                                               ("warn" if "⚠" in status else "unknown"))
        rows.append(dict(name=name, state=state, status=status, evidence=evid))
    return rows


def check_report_consistency(reports):
    """战报自洽：声称 PASS 却无证据 = 幻觉自证；PASS 数骤降 = 覆盖退化。"""
    if not reports:
        return [dict(id="selfproof", level="warn", title="证据自洽",
                     detail="无战报可校验", value=None)]
    last = reports[-1]
    rows = parse_report_sources(last.read_text(encoding="utf-8", errors="ignore"))
    out = []
    if not rows:
        out.append(dict(id="selfproof", level="warn", title="证据自洽",
                        detail=f"{last.name} 未找到信号源表，无法校验", value=None))
    else:
        naked = [r["name"] for r in rows
                 if r["state"] == "pass" and r["evidence"] in ("", "—", "-")]
        passes = [r for r in rows if r["state"] == "pass"]
        blocked = [r for r in rows if r["state"] == "blocked"]
        if naked:
            out.append(dict(id="selfproof", level="fail", title="证据自洽",
                            detail="声称 PASS 但无证据列：" + "、".join(naked), value=len(naked)))
        else:
            out.append(dict(id="selfproof", level="ok", title="证据自洽",
                            detail=f"{len(passes)}/{len(rows)} 源 PASS，全部附证据", value=len(passes)))
        if len(blocked) > 1:
            out.append(dict(id="coverage", level="warn", title="观察覆盖",
                            detail=f"{len(blocked)} 个信号源 blocked（" +
                                   "、".join(r["name"] for r in blocked) + "）", value=len(blocked)))
        else:
            out.append(dict(id="coverage", level="ok", title="观察覆盖",
                            detail=f"仅 {len(blocked)} 源 blocked" if blocked else "6/6 源在线", value=len(blocked)))
    return out


def check_evidence_freshness(reports):
    """原始证据 vs 战报的时间关系：证据比战报还旧 = 拿上次的绿灯冒充本轮。"""
    logs = sorted(LOGS.glob("sdk_test_*.log"), key=lambda p: p.stat().st_mtime)
    if not logs:
        return dict(id="evidence", level="fail", title="证据新鲜度",
                    detail="test_logs/ 无任何 sdk_test 日志 —— 单测证据缺失", value=None)
    newest = logs[-1]
    text = newest.read_text(encoding="utf-8", errors="ignore")
    m = re.findall(r"Executed (\d+) tests?, with (\d+) failures?", text)
    if m:
        total, fails = int(m[-1][0]), int(m[-1][1])
    else:
        total, fails = None, None
    lag = None
    if reports:
        lag = (reports[-1].stat().st_mtime - newest.stat().st_mtime) / 60.0
    detail = f"{newest.name} · " + (f"{total} tests / {fails} failures" if total is not None else "未解析到计数")
    if fails:
        return dict(id="evidence", level="fail", title="证据新鲜度",
                    detail=detail + f" · {fails} 个失败", value=fails)
    if lag is not None and lag > 60:
        return dict(id="evidence", level="warn", title="证据新鲜度",
                    detail=detail + f" · 证据比战报早 {lag/60:.1f}h，疑似沿用旧绿灯", value=lag)
    return dict(id="evidence", level="ok", title="证据新鲜度",
                detail=detail + " · 与战报同步", value=total)


def parse_pool():
    if not TODOS.exists():
        return {}
    items = []
    for line in TODOS.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^\|\s*([A-Z]+-\d+)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|", line)
        if not m:
            continue
        items.append(dict(id=m.group(1).strip(), title=m.group(2).strip(),
                          prio=m.group(3).strip(), status=m.group(4).strip()))
    return items


def norm_status(s):
    s = s.replace("✅", "").strip()
    for key, val in (("ready-for-review", "rfr"), ("self-verify", "self-verify"),
                     ("待需求审核", "待审核"), ("待审核", "待审核"), ("已审核", "已审核"),
                     ("doing", "doing"), ("blocked", "blocked"), ("done", "done")):
        if s.startswith(key):
            return val
    return s


def last_touch(item_id):
    """该单在 TODOS.md 里最后一次被改动的时间。

    用 -G 而非 -S：-S 数的是字符串出现次数，只改备注（单号出现次数不变）会漏判。
    """
    out = sh(["git", "log", "-1", "--format=%at", "-G", re.escape(item_id), "--", "TODOS.md"])
    try:
        return float(out.splitlines()[0])
    except Exception:
        return TODOS.stat().st_mtime


def check_metabolism(items):
    out = []
    by = {}
    for it in items:
        by.setdefault(norm_status(it["status"]), []).append(it)

    stuck = []
    for st, limit in (("doing", DOING_WARN_H), ("self-verify", DOING_WARN_H), ("rfr", RFR_WARN_H)):
        for it in by.get(st, []):
            h = hours_ago(last_touch(it["id"]))
            if h > limit:
                stuck.append(f"{it['id']}({st}, {h:.0f}h)")
    if stuck:
        out.append(dict(id="flow", level="warn", title="池子流动",
                        detail="滞留：" + "、".join(stuck), value=len(stuck)))
    else:
        out.append(dict(id="flow", level="ok", title="池子流动",
                        detail="无 doing/rfr 滞留", value=0))

    ready = len(by.get("已审核", []))
    todo = len(by.get("待审核", []))
    rfr = len(by.get("rfr", []))
    detail = f"已审核 {ready} · 待审核 {todo} · rfr {rfr}"
    if ready == 0 and todo == 0:
        out.append(dict(id="queue", level="warn", title="待执行队列",
                        detail=detail + " · 池空，循环会空转（需要新需求）", value=0))
    elif ready == 0:
        out.append(dict(id="queue", level="warn", title="待执行队列",
                        detail=detail + " · 无可执行单，全卡在审核关卡", value=0))
    else:
        out.append(dict(id="queue", level="ok", title="待执行队列", detail=detail, value=ready))
    return out


SRC_DIRS = ("AudioRecordApp/", "AudioRecordKit/", "e2e/")


def check_integrity(reports):
    """完整性：master 上的源码改动只能来自「验收后合并」，不能来自某轮 loop 自己。

    判定窗口 = 最近一份战报之后。那之后若出现触碰源码目录的直达提交，
    说明有人（大概率是无人值守的 loop）绕过 worktree 直接改了主干。
    战报可以自己吹，git 的提交链不会。
    """
    branch = sh(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    if branch not in ("master", "main"):
        return dict(id="integrity", level="warn", title="master 完整性",
                    detail=f"当前在 {branch}，不是 master，跳过校验", value=None)

    since = None
    if reports:
        since = datetime.fromtimestamp(reports[-1].stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")

    src_hits, churn = [], 0
    if since:
        raw = sh(["git", "log", f"--since={since}", "--no-merges",
                  "--pretty=format:@@%h %s", "--name-only", "master"])
        cur = None
        for line in raw.splitlines():
            if line.startswith("@@"):
                cur = line[2:].strip()
            elif line.strip() and cur:
                if line.startswith(SRC_DIRS):
                    src_hits.append((cur, line.strip()))
        churn = sh(["git", "rev-list", "--count", f"--since={since}",
                    "--no-merges", "master"])

    dirty = [l for l in sh(["git", "status", "--porcelain"]).splitlines()
             if l.strip() and any(l[3:].startswith(d) for d in SRC_DIRS)]
    wt = [l for l in sh(["git", "worktree", "list"]).splitlines() if l.strip()]

    detail = (f"窗口起点 {since or '无战报'} · 窗口内直达提交 {churn or 0} · "
              f"worktree {max(len(wt)-1, 0)} 个")
    if src_hits:
        msg, path = src_hits[0]
        return dict(id="integrity", level="fail", title="master 完整性",
                    detail=detail + f" · ⛔ 源码被直达提交 {len(src_hits)} 处，如 {msg[:40]} 改 {path}",
                    value=len(src_hits))
    if dirty:
        return dict(id="integrity", level="warn", title="master 完整性",
                    detail=detail + f" · master 工作区有 {len(dirty)} 个源码改动未提交",
                    value=len(dirty))
    return dict(id="integrity", level="ok", title="master 完整性",
                detail=detail + " · 窗口内源码零直达提交", value=0)


def check_schedule():
    """这个脚本读不到自动化清单，如实标为人工项，不假装能自检。"""
    return dict(id="schedule", level="ok", title="触发方式",
                detail="当前=手动触发（无常驻调度）。挂定时后本项改判：>26h 无轮次即报警",
                value="manual")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-log", action="store_true")
    args = ap.parse_args()

    reports = sorted(REPORTS.glob("R*-*.md"), key=lambda p: p.stat().st_mtime)
    checks = [check_heartbeat(reports)]
    checks += check_report_consistency(reports)
    checks.append(check_evidence_freshness(reports))
    items = parse_pool()
    checks += check_metabolism(items)
    checks.append(check_integrity(reports))
    checks.append(check_schedule())

    worst = "ok"
    for c in checks:
        if c["level"] == "fail":
            worst = "fail"
            break
        if c["level"] == "warn":
            worst = "warn"

    payload = dict(ts=datetime.now().astimezone().isoformat(timespec="seconds"),
                   verdict=worst, checks=checks)
    if not args.no_log:
        with open(REPORTS / "health.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(dict(ts=payload["ts"], verdict=worst,
                                    fails=[c["id"] for c in checks if c["level"] == "fail"],
                                    warns=[c["id"] for c in checks if c["level"] == "warn"]),
                               ensure_ascii=False) + "\n")

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(f"LoopBuddy 体检 · {payload['ts']}")
        print("─" * 64)
        for c in checks:
            print(f"{ICON[c['level']]} {c['title']:<8} {c['detail']}")
        print("─" * 64)
        print({"ok": "结论：健康，循环在转",
               "warn": "结论：有警告，优先看 ⚠️ 项（多为缺单或调度断）",
               "fail": "结论：有失败，循环已不可信，立刻看 ⛔ 项"}[worst])

    return {"ok": 0, "warn": 1, "fail": 2}[worst]


if __name__ == "__main__":
    sys.exit(main())
