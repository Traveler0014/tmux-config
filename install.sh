#!/usr/bin/env sh
# ============================================================
# tmux-config 安装脚本
# 把本仓库 symlink 到标准位置，并生成本机私有配置
# 用法: ./install.sh
# ============================================================
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="${HOME}/.local/bin"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

backup_if_real() {
  # $1 = 目标路径；存在且不是 symlink 时改名备份
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    mv "$1" "$1.bak.$(date +%s)"
    echo "已备份: $1 → $1.bak.*"
  fi
}

mkdir -p "$CFG" "$BIN" "$DATA/tmux/layouts"

# 1) XDG 配置目录（整个目录镜像）
backup_if_real "$CFG/tmux"
ln -sfn "$REPO_DIR/.config/tmux" "$CFG/tmux"
echo "已链接: $CFG/tmux → $REPO_DIR/.config/tmux"

# 2) 旧 ~/.tmux.conf 必须让位
#    tmux 的查找顺序是 ~/.tmux.conf 优先于 ~/.config/tmux/tmux.conf，
#    旧文件存在会让 XDG 配置完全不生效。
if [ -L "$HOME/.tmux.conf" ]; then
  rm -f "$HOME/.tmux.conf"
  echo "已移除旧 symlink: $HOME/.tmux.conf"
elif [ -e "$HOME/.tmux.conf" ]; then
  backup_if_real "$HOME/.tmux.conf"
fi

# 3) 布局脚本
chmod +x "$REPO_DIR/bin/tmux-layout"
ln -sfn "$REPO_DIR/bin/tmux-layout" "$BIN/tmux-layout"
echo "已链接: $BIN/tmux-layout → $REPO_DIR/bin/tmux-layout"

# 4) 本机私有配置模板
if [ ! -f "$REPO_DIR/.config/tmux/90-local.conf" ]; then
  cp "$REPO_DIR/.config/tmux/90-local.conf.example" "$REPO_DIR/.config/tmux/90-local.conf"
  echo "已创建 90-local.conf（来自 .example，不入库）"
fi

echo "=================================================="
echo "安装完成。验证:"
echo "  tmux kill-server; tmux new -s main     # 重新加载配置"
echo "  tmux info | grep -i sixel              # 应显示 Sxl: (bool) true"
echo "  tmux-layout list                       # 布局模板列表"
echo "  prefix + S 保存布局 / prefix + L 载入布局"
