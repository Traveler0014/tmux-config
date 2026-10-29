# 这里放「想入库复用」的布局模板（tmux-layout save 的产物可以拷进来）

tmux-layout save 出来的模板是一个纯文本文件，语法如下，可手写：

```
# 注释行
meta|1|<session 名>
window|<窗口号>|<窗口名>|<是否激活>|<tmux layout 串>
pane|<窗口号>|<pane 号>|<top>|<left>|<宽>x<高>|<是否激活>|<当前命令>|<当前目录>
```

恢复时 window / pane 按记录的顺序与几何位置重建，
`pane` 行里的「当前命令」只在 `tmux-layout load --with-programs` 时才回放。

放在本目录的模板对所有机器可用（脚本会同时搜索
`$XDG_DATA_HOME/tmux/layouts` 与本目录）。
