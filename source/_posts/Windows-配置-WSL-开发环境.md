---
title: Windows 配置 WSL 开发环境
date: 2019-1-08 19:03:40
tags:
categories:
- wsl
---

[TOC]

## WSL 常用操作
### 安装 WSL

1. 打开 PowerShell 运行：

```
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
```

2. 在 Windows 商店安装 Ubuntu 18.04


### WSL 切换

wslconfig.exe 可以管理系统已安装的发行版，和设置默认的发行版：

```
~$ wslconfig.exe /list
适于 Linux 的 Windows 子系统:
Ubuntu (默认)
```

`wslconfig /list` ：列出 WSL 可用的 Linux 发行版。如果列出了分发版，则会安装并准备使用。

`wslconfig /list /all`: 列出 WSL 所有发行版，包括正在安装，或者安装失败的

`wslconfig /unregister <DistributionName>`： 从 WSL 发行版中取消注册，执行 `wslconfig /list` 将无法显示

`wslconfig /setdefault <DistributionName>`: 设置默认的发行版 

> 例如： `wslconfig /setdefault Ubuntu`  设置默认 wsl 使用 ubuntu ， 运行 `wsl npm init` 就会在 ubuntu 中运行该命令


### 密码重置

打开 `cmd` , 设置启动用户为 root

```
C:\> ubuntu config --default-user root
```

启动 ubuntu.exe , 此时用户将是 root ，在 `bash` 中执行

```
$ passwd username
```

将用户切回普通用户，在 `cmd` 中执行

```
C:\> ubuntu config --default-user username
```


## 安装 VcXsrv

由于 xming 已经不维护了，vscode 安装会有问题，使用 VcXsrv 则没有那些问题

地址 https://sourceforge.net/projects/vcxsrv/


设置 XLaunch

- 全屏使用: 点击 One Window without titlebar，点击下一步

- 窗口使用：点击 multiple windows ，点击下一步

- 点击 Start no client，点击下一步

- 勾选 Disable access control ，点击下一步，点击完成


Windows 开启一个新的虚拟桌面 `Win + Ctrl + D` ,切换虚拟桌面 `Win + Ctrl +左/右` , 并启动 XLaunch 

关闭虚拟桌面为 `Win + Ctrl + F4`



## 初始化 WSL

安装常用软件，和初始化 wsl

```
curl https://github.com/kuops/Scripts/blob/master/bash/wsl-init.sh|sudo bash
```

如果中文输入法有问题，使用 `fcitx-diagnose` 排错

```
fcitx-diagnose
```

## 设置 Cmder

由于 conemu 使用 wsl vim 使用非常慢，而 cmder 没有这个问题，Windows 安装 cmder

下载地址： http://cmder.net/


## 设置 VScode

如果使用 windows 的 vscode 则 settings.json 设置

```
{
"terminal.integrated.shell.windows": "C:\\Windows\\System32\\wsl.exe",
"files.autoSave": "afterDelay",
"go.goroot": "C:\\Go",
"go.gopath": "C:\\Code\\go_workspace",
"terminal.integrated.fontFamily": "Source Code Pro for Powerline",
}
```

复制路径，安装一个插件 `Copy WSL Path` ，可以复制 windows 路径为 WSL 路径


## 设置 tmux

tmux 主要特点有两个：

- 多窗口操作，在一个终端分出多个终端
- 避免 SSH 连接不稳定，断开前台任务问题

> 在开启了 tmux 服务器后，会首先创建一个会话，而这个会话则会首先创建一个 窗口，其中仅包含一个面板；也就是说，这里看到的所谓终端控制台应该称作 tmux 的一个面板， 虽然其使用方法与终端控制台完全相同。

tmux使用 C/S 模型构建，主要包括以下单元模块：

- server服务器: 输入tmux命令时就开启了一个服务器。
- session会话: 一个服务器可以包含多个会话
- window窗口: 一个会话可以包含多个窗口。
- pane面板: 一个窗口可以包含多个面板。

TMUX 中文指南 https://www.kancloud.cn/kancloud/tmux/62459


### 常规操作 


session 管理

```
tmux                      # 创建新的 session
tmux new -S name          # 创建新的 session 并指定 name
tmux ls                   # 查看 session 列表
tmux a 或 tmux at 或 tmux attach   # 如果当前仅有一个 session，重新连接该 session
tmux a -t num             # 如果有多个 session, 指定 session num 连接
tmux kill-session -t name     # kill 名称为 name 的 session
tmux kill-session -a          # kill 所有 session, 除了当前的 session
tmux kill-session -a -t name  # kill 所有 session, 除了 name
```

常用快捷键

```
ctrl + b       # prefix 键，在操作所有快捷键之前需要按 prefix 键，并松开，之后按其他快捷键
prefix + ？    # 显示帮助
prefix + s     # 显示会话
prefix + (     # 切换到上一会话
prefix + )     # 切换到下一会话
prefix + $     # 重命名会话
prefix + c     # 新建窗口
prefix + w     # 列出窗口
prefix + n     # 下一个窗口
prefix + p     # 上一个窗口
prefix + &     # 关闭当前窗口
prefix + ,     # 重命名窗口
prefix + [1-9] # 切换窗口
prefix + "     # 添加一行分面板
prefix + %     # 添加一列分面板
prefix + q     # 显示分割面板编号
prefix + o     # 切换到下一面板
prefix + ;     # 切换到最后一个使用的面板
prefix + 方向键  # 切换面板
prefix + x   # 关闭当前面板
prefix + (ctrl + 方向键)  # 调整面板大小
prefix + d   # 退出tumx，tmux 仍在后台运行，可以通过tmux attach进入 到指定的会话
```

复制模式, 按下 `PREFIX-[` 即可进入复制模式，

设置 `tmux.conf` 通过 vim 的快捷键实现浏览, 复制等操作：

```
setw -g mode-keys vi
```


### 复制模式

添加下面一行到 $HOME/.tmux.conf, 通过 vim 的快捷键实现浏览, 复制等操作;

```bash
setw -g mode-keys vi
```


| 按键                 | 说明                                       |
| ------------------   | ---                                        |
| `prefix + [`         | 进入复制模式                               |
| `prefix + ]`         | 粘贴选择内容(粘贴 buffer_0 的内容)         |
| :show-buffer         | 显示 buffer_0 的内容                       |
| :capture-buffer      | 复制整个能见的内容到当前的 buffer          |
| :list-buffers        | 列出所有的 buffer                          |
| :choose-buffer       | 列出所有的 buffer, 并选择用于粘贴的 buffer |
| :save-buffer buf.txt | 将 buffer 的内容复制到 buf.txt             |
| :delete-buffer -b 1  | 删除 buffer_1                              |

| vi     | emacs     | 功能                 |
| ------ | --------- | ---                  |
| ^      | M-m       | 跳转到一行开头       |
| Escape | C-g       | 放弃选择             |
| k      | Up        | 上移                 |
| j      | Down      | 下移                 |
| h      | Left      | 左移                 |
| l      | Right     | 右移                 |
| L      |           | 最后一行             |
| M      | M-r       | 中间一行             |
| H      | M-R       | 第一行               |
| $      | C-e       | 跳转到行尾           |
| :      | g         | 跳转至某一行         |
| C-d    | M-Down    | 下翻半页             |
| C-u    | M-Up      | 上翻半页             |
| C-f    | Page down | 下翻一页             |
| C-b    | Page up   | 上翻一页             |
| w      | M-f       | 下一个字符           |
| b      | M-b       | 前一个字符           |
| q      | Escape    | 退出                 |
| ?      | C-r       | 往上查找             |
| /      | C-s       | 往下查找             |
| n      | n         | 查找下一个           |
| Space  | C-Space   | 进入选择模式         |
| Enter  | M-w       | 确认选择内容, 并退出 |


### tmux 配置文件

设置 `~/.tmux.conf`

```
# 设置复制模式，空格开始选，Enter结束复制
setw -g mode-keys vi

# 设置颜色
set -g default-terminal "screen-256color"

# 开启剪切板
set -g set-clipboard on

# 设置历史记录限制
set -g history-limit 102400

# 关闭窗口后重新编号
set -g renumber-windows on

# 安装 yank 插件，系统复制粘贴用，wsl 依赖 clip.exe 命令
set -g @plugin 'tmux-plugins/tmux-yank'
```
