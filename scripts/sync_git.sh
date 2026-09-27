#!/usr/bin/env bash
# ==============================================================================
# Git 自動保存與 GitHub 同步腳本
# ==============================================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# 確保已初始化 git
if [ ! -d ".git" ]; then
    echo "正在初始化 Git 儲存庫..."
    git init
    git branch -M main
fi

# 加入更改並自動 commit
git add .
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
if git diff --cached --quiet; then
    echo "[$TIMESTAMP] 沒有檢測到任何代碼或配置變更，無需 Commit。"
else
    git commit -m "Auto-backup: $TIMESTAMP"
    echo "[$TIMESTAMP] 已在本地成功建立 Commit。"
fi

# 如果有設定遠端 origin 則推送到 GitHub
if git remote | grep -q "origin"; then
    echo "檢測到遠端 GitHub 儲存庫，正在推送變更..."
    git push -u origin main
    echo "已成功同步至 GitHub！"
else
    echo "提示：目前尚未綁定 GitHub 遠端儲存庫。"
    echo "如需綁定，請執行："
    echo "  git remote add origin https://<YOUR_GITHUB_TOKEN>@github.com/<USERNAME>/<REPO>.git"
    echo "  git push -u origin main"
fi
