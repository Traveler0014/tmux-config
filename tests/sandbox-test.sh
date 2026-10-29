#!/usr/bin/env bash
# 沙箱自测：用独立 HOME + 独立 socket 验证 install.sh 与 tmux-layout 往返
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SB=/tmp/tmuxcfg-sandbox
export HOME="$SB/home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export TMUX_TMPDIR="$SB/sock"
export PATH="$HOME/.local/bin:$PATH"
export TMUX_LAYOUT_TEMPLATES="$REPO/layouts"
rm -rf "$SB"; mkdir -p "$HOME" "$TMUX_TMPDIR"

pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: 期望 [$3] 实际 [$2]"; fi; }
snap() { tmux list-panes -a -F '#{window_index}.#{pane_index} #{pane_id} top=#{pane_top} left=#{pane_left} size=#{pane_width}x#{pane_height} start=#{pane_start_path} cwd=#{pane_current_path}' | sort; }

echo "== 1. install.sh 在干净 HOME 上运行 =="
out=$("$REPO/install.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/  | /'
chk "install.sh 退出码" "$rc" "0"
chk "~/.config/tmux 是 symlink" "$([ -L "$HOME/.config/tmux" ] && echo yes || echo no)" "yes"
chk "tmux-layout 可执行" "$([ -x "$HOME/.local/bin/tmux-layout" ] && echo yes || echo no)" "yes"
chk "90-local.conf 已生成" "$([ -f "$REPO/.config/tmux/90-local.conf" ] && echo yes || echo no)" "yes"

echo "== 2. 配置能被 tmux 读取（含 source-file ~ 展开）=="
tmux new-session -d -s probe -c /tmp 2>/dev/null
sleep 0.2
chk "default-terminal" "$(tmux show -gv default-terminal)" "tmux-256color"
chk "escape-time" "$(tmux show -gv escape-time)" "10"
chk "history-limit" "$(tmux show -gv history-limit)" "50000"
chk "focus-events" "$(tmux show -gv focus-events)" "on"
chk "set-clipboard" "$(tmux show -gv set-clipboard)" "on"
chk "allow-passthrough" "$(tmux show -gv allow-passthrough)" "on"
chk "extended-keys" "$(tmux show -gv extended-keys)" "on"
chk "extended-keys-format" "$(tmux show -gv extended-keys-format)" "csi-u"
chk "mouse" "$(tmux show -gv mouse)" "on"
chk "sixel 能力条目数" "$(tmux show -gv terminal-features | grep -c sixel)" "2"
chk "bind S(保存布局)" "$(tmux list-keys | grep -cE '^bind-key.*[[:space:]]S[[:space:]]+command-prompt')" "1"
chk "bind L(载入布局)" "$(tmux list-keys | grep -cE '^bind-key.*[[:space:]]L[[:space:]]+run-shell.*tmux-layout')" "1"

echo "== 3. 造 3 窗口 / 7 pane / 各不同 cwd =="
mkdir -p /tmp/tmuxcfg-d/proj /tmp/tmuxcfg-d/logs /tmp/tmuxcfg-d/build /tmp/tmuxcfg-d/db
tmux kill-session -t probe 2>/dev/null
tmux new-session -d -s work -n editor -c /tmp/tmuxcfg-d/proj
tmux split-window -t work:editor -c /tmp/tmuxcfg-d/logs -l 30%
tmux split-window -t work:editor -c /tmp/tmuxcfg-d/build -l 30%
tmux select-layout -t work:editor main-vertical >/dev/null
tmux new-window -d -t work:2 -n ops -c /tmp/tmuxcfg-d/db
tmux split-window -t work:2 -c /tmp/tmuxcfg-d/logs
tmux new-window -d -t work:3 -n misc -c /tmp
tmux split-window -t work:3 -c /usr -h
sleep 0.6
snap > "$SB/before.txt"
sed 's/^/  | /' "$SB/before.txt"

echo "== 4. save =="
tmux-layout save t1 work 2>&1 | sed 's/^/  | /'
chk "模板文件存在" "$([ -f "$XDG_DATA_HOME/tmux/layouts/t1.conf" ] && echo yes || echo no)" "yes"
echo "  --- 模板内容 ---"
sed 's/^/  | /' "$XDG_DATA_HOME/tmux/layouts/t1.conf"

echo "== 5. kill 之后 load，按位置序对比 =="
tmux kill-session -t work
tmux-layout load t1 -d 2>&1 | sed 's/^/  | /'
sleep 1
snap > "$SB/after.txt"
sed 's/^/  | /' "$SB/after.txt"

# 位置签名：window / top,left / size / cwd —— pane_id 与 pane 序号允许重排
sig() { sed -E 's/^([0-9]+)\.[0-9]+ %[0-9]+ /\1 /; s/ start=[^ ]+//' "$1" | sort; }
sig "$SB/before.txt" > "$SB/b.sig"
sig "$SB/after.txt"  > "$SB/a.sig"
if diff -u "$SB/b.sig" "$SB/a.sig" > "$SB/diff.txt"; then
  ok "每个位置的 cwd / 几何完全还原"
else
  bad "位置 → cwd/几何 有差异"; sed 's/^/  | /' "$SB/diff.txt"
fi

echo "== 6. 异常路径 =="
tmux-layout load t1 >/dev/null 2>&1 && bad "重名 session 应报错" || ok "重名 session 正确报错"
tmux-layout load nope >/dev/null 2>&1 && bad "缺失模板应报错" || ok "缺失模板正确报错"
tmux-layout save 'bad name' >/dev/null 2>&1 && bad "非法名字应报错" || ok "非法模板名正确报错"
tmux-layout show t1 >/dev/null 2>&1 && ok "show 正常" || bad "show 失败"
tmux-layout list 2>&1 | sed 's/^/  | /'
tmux-layout rm t1 >/dev/null 2>&1 && ok "rm 正常" || bad "rm 失败"

echo "== 清理 =="
tmux kill-server 2>/dev/null
rm -rf /tmp/tmuxcfg-d
echo
echo "结果: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
