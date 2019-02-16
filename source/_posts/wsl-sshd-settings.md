---
title: WSL 配置 SSHD 访问
date: 2019-02-16 13:59:40
tags:
categories:
- wsl
---

## sudo 免密

```
yourname    ALL=(ALL)    NOPASSWD: ALL
```

## wsl 安装 ssh

在 ubuntu(wsl) 中安装 openssh-server

```
sudo apt-get install openssh-server -y
sudo sed -ri 's@(PasswordAuthentication ).*@\1 yes@' /etc/ssh/sshd_config
sudo sed -ri 's@#?UseDNS no@UseDNS no@' /etc/ssh/sshd_config
```

## windows 开机启动脚本

脚本存放路径，windows 的开机启动路径，win10 当前用户路径为：

```
C:\Users\%USERNAME%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```

将以下内存保存为 `sshd.vbs` 存放在以上目录中：

```
set ws=wscript.createobject("wscript.shell")
ws.run "C:\Windows\System32\bash.exe -c 'sudo service ssh --full-restart'",0
```

如果需要在使用 wsl 的 vagrant ，或者 windows 其他命令，ssh 登录默认的 PATH 变量中缺少一些系统 PATH ，在 bash.exe 执行以下命令：

```
echo $PATH
```

将变量的值写入 ~/.zshrc 或 ~/.bashrc

```
PATH="values"
```


