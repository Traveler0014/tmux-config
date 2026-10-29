# tmux-config

个人 tmux 配置：模块化、零依赖、可保存/恢复 session 布局。

## 特性

- **模块化加载**：`~/.config/tmux/` 下按序 source（`00-options` → `30-sixel` → `40-layouts` → `90-local`），文件缺失自动跳过
- **零依赖**：不用 tpm，不引第三方插件；布局脚本是纯 bash
- **布局模板化**：`prefix+S` 把当前 session 的「窗口划分 + 每个 pane 的目录」存成纯文本模板，`prefix+L` 一条命令还魂；模板可入库跨机器复用
- **图形协议**：sixel 配置 + `tmux-sixel-check` 自检脚本（含 WSL/ConPTY 下 `client_cell_width=0` 的诊断）
- **机器隔离**：机器相关项写 `90-local.conf`（gitignore，install.sh 从 `.example` 生成）
- **键位保守**：除 `prefix+S` / `prefix+L` 两个新增键，其余保持 tmux 默认习惯

## 目录结构

```
tmux-config/
├── install.sh                     # 一键安装（symlink 到标准位置）
├── bin/tmux-layout                # 布局保存/恢复脚本（零依赖）
├── bin/tmux-sixel-check           # sixel 可用性自检（含出图测试）
├── .config/tmux/
│   ├── tmux.conf                  # 薄入口：只控制加载顺序
│   ├── 00-options.conf            # 终端能力 / 历史 / 焦点 / 扩展键 / 鼠标
│   ├── 30-sixel.conf              # 图形协议（sixel）+ terminal-features
│   ├── 40-layouts.conf            # prefix+S / prefix+L 键位
│   ├── 90-local.conf.example      # 本机私有配置模板
│   └── 90-local.conf              # 本机私有（不入库）
├── layouts/                       # 想入库复用的布局模板（+ 格式说明）
└── tests/sandbox-test.sh          # 沙箱自测（独立 HOME + 独立 socket）
```

## 安装

```sh
git clone git@github.com:Traveler0014/tmux-config.git ~/github/tmux-config
cd ~/github/tmux-config && ./install.sh
```

install.sh 会：

1. `~/.config/tmux` → 仓库 `.config/tmux`（原目录存在则备份为 `*.bak.<时间戳>`）
2. 把旧的 `~/.tmux.conf` 备份掉——**必须让位**，否则 tmux 优先读它，XDG 配置完全不生效
3. `~/.local/bin/tmux-layout` → 仓库 `bin/tmux-layout`
4. 从 `90-local.conf.example` 生成本机 `90-local.conf`（若不存在）

验证：

```sh
tmux kill-server; tmux new -s main
tmux info | grep -i sixel     # 应显示 Sxl: (bool) true
tmux-layout list
```

## 布局保存 / 恢复

```sh
# 在 tmux 里
prefix + S          # 输入模板名，保存当前 session
prefix + L          # 菜单里挑一个模板，恢复成新 session

# 命令行
tmux-layout save work            # 保存当前 session 为 work
tmux-layout save work mysession  # 保存指定 session
tmux-layout load work            # 恢复（session 名沿用模板里的名字）
tmux-layout load work -n work2   # 换个 session 名恢复
tmux-layout load work -d         # 只恢复，不 attach/switch
tmux-layout load work --with-programs   # 连当时跑的命令一起回放（默认不回放）
tmux-layout list | show <名> | rm <名>
```

模板格式（纯文本、可 diff、可手写）：

```
# tmux-layout v1  session=work  saved=2026-10-29T15:19:03+08:00
meta|1|work
window|0|editor|1|b0a5,80x24,0,0{78x24,0,0,0,1x24,79,0[1x11,79,0,1,1x12,79,12,2]}
pane|0|0|0|0|78x24|0|zsh|/home/novart/proj
pane|0|1|0|79|1x11|0|zsh|/home/novart/logs
```

- 模板默认存在 `${XDG_DATA_HOME:-~/.local/share}/tmux/layouts/`（`TMUX_LAYOUT_DIR` 可改）
- 脚本也会搜索仓库 `layouts/`，所以想跨机器复用的模板直接提交进去
- 恢复只还原「结构 + 目录 + 激活窗口/pane」，不还原 shell 历史与进程状态（要连命令一起回放用 `--with-programs`）
- 已知边界：pane 路径里若含 `|` 会被截断；模板名限制 `[A-Za-z0-9._-]`

### 实现要点（为什么这样做）

1. `#{window_layout}` 串里的校验和只覆盖**结构**、不含尺寸，所以原样保存后，在任意大小的窗口里 `select-layout` 都能贴回去。
2. 布局串里的编号不是稳定的 pane 身份，恢复时用 `(top,left)` 排序做**位置序配对**，再把每个 pane `respawn-pane -c` 回原目录——否则路径会串位（实测过）。

## 图形协议（sixel）

tmux 3.5 起是**自己解析 + 自己绘制**（不是简单透传）：它先对 pane 里的应用「假装」支持 sixel（DA1 回属性 4），应用于是真的吐 sixel；tmux 解析后按外层终端的单元格像素尺寸缩放重编码再输出。任一条件不满足就退化成 `SIXEL IMAGE (WxH)` + 一串 `+` 的文字占位符。

`30-sixel.conf` 做的事：

```tmux
set -as terminal-features ',xterm*:RGB:clipboard:hyperlinks:focus:sync:extkeys'
set -as terminal-features ',wezterm*:sixel'
set -g allow-passthrough on
```

### 本机（WSL2 + WezTerm）实测结论

| 环节 | 状态 |
|---|---|
| WezTerm 是否支持 sixel | ✅ DA1 = `ESC[?65;4;6;18;22;52c`，属性 4 在 |
| tmux 是否知道终端支持 sixel | ✅ `terminal-features` + `#{client_termfeatures}` 含 sixel |
| tmux 是否知道**单元格像素尺寸** | ❌ WSL/ConPTY 的 pty 报 `ws_xpixel=0`；tmux 3.5a 只读 ioctl、不会主动问终端 |
| 结果 | tmux 3.5a：必然显示 `SIXEL IMAGE (3x2)` 占位文本 |
| 修法 | 升级 tmux 到 **≥ 3.6**（会发 `CSI 18t` / `CSI 14t` 询问像素尺寸，WezTerm 正常应答 `ESC[8;43;190t` / `ESC[4;946;1900t`） |

验证实验（同一份 tmux 3.5a 二进制，只改 pty 上报的像素尺寸）：

```
pty 报 ws_xpixel=0     → 输出 "SIXEL IMAGE (3x2)" 占位文本
pty 报 ws_xpixel=1200  → 输出真实 sixel：ESC P q "1;1;50;36 #0;0;0;0;0 ...
```

所以**配置侧无解**，只能升级 tmux。自检脚本会直接告诉你 `client_cell_width` 是不是 0：

```sh
tmux-sixel-check          # 在 tmux 里跑
```

### 其它限制（tmux 侧固有）

| 项 | 说明 |
|---|---|
| 单图上限 | 1MB（[tmux#4161](https://github.com/tmux/tmux/issues/4161)），大图被静默丢弃 |
| 重绘 | 滚动 / 切 pane / 重绘后图像可能残留或错位 |
| kitty 图形协议 | tmux 不支持（只认 sixel）；WezTerm 两者都支持，但 tmux 只走 sixel |

换到不支持 sixel 的终端时，把两行 `sixel` 注释掉即可，其它 feature 与图形无关。

## 依赖

| 类别 | 需要 | 缺失时 |
|---|---|---|
| 必需 | tmux ≥ 3.4（sixel 透传 + `terminal-features`）、bash 4+ | 老版本 tmux 下 sixel 行不生效，其余功能正常 |
| 可选 | `fzf`（未使用）、tpm（不使用） | — |

## 测试

```sh
./tests/sandbox-test.sh
```

用独立 `HOME` + 独立 `TMUX_TMPDIR` 跑完：install 幂等性 → 配置项是否生效 → 造 3 窗口 / 7 pane 的 session → 保存 → 杀掉 → 恢复 → 逐位置比对 cwd 与几何 → 异常路径。
