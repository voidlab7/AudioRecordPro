#!/bin/bash
# 安装 git 钩子：core.hooksPath 指向仓库内 scripts/hooks（可入库追溯，克隆后跑一次即生效）。
# 效果：
#   - post-merge：master 每次 git merge/pull 合入新提交后自动版本化构建
#   - post-commit：master 上的「合并提交」（冲突解决后 commit 收尾）同样自动构建
#   - 两者都会打出 DMG、tag v<版本> 并上传 GitHub Release（gh 已登录时）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/scripts/hooks/post-merge" "$ROOT/scripts/hooks/post-commit"
git -C "$ROOT" config core.hooksPath scripts/hooks
echo "✅ hooks 已安装：master 每次合并后自动构建 + DMG + GitHub Release"
echo "   验证：git -C $ROOT config core.hooksPath   # 应输出 scripts/hooks"
echo "   日志：releases/logs/*.log"
