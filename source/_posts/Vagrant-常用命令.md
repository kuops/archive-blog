---
title: Vagrant 常用命令
date: 2018-05-03 23:36:53
categories:
- vagrant
---

## box 

用于添加删除 box 等，又以下子命令

- add
- list
- outdated
- prune
- remove
- repackage
- update

**Box Add**
```
vagrant box add ADDRESS
```

addreess 可以是以下三种任意一种：

- Vagrant 公共镜像简写名称 ，如 "hashicorp/precise64"。
- 文件路径或 `HTTP URL` 到目录中的框。对于HTTP，支持基本身份验证并且支持通过 `http_proxy` 变量进行下载 。HTTPS也受支持。
- 网址直接一个盒子文件。在这种情况下，您必须指定一个--name标志，版本控制/更新将不起作用。

**其他子命令**

|命令|说明|
|---|---|
|vagrant box list | 列出当前所有的 box|
|vagrant box outdated | 告诉你当前 vagrant 环境中使用的 box 是否过期|
|vagrant box prune | 清理旧版本的 box，如果当前 box 正在使用，则要求使用者确认|
|vagrant box remove NAME| 从Vagrant 中删除与给定名称相匹配的 box|
|vagrant box repackage NAME PROVIDER VERSION|该命令重新打包给定的 box 并将其放入当前目录，以便重新分配它。该 box 的名称，提供者和版本可以使用 vagrant box list 查看|
|vagrant box update|更新 box|

## destroy

```
vagrant destroy [name|id]
```

该命令停止正在运行的机器Vagrant正在管理并销毁机器创建过程中创建的所有资源。运行此命令后，您的计算机应保持清洁状态，就好像您从未创建客户机一样。
当前登录用户系统上所有活动的Vagrant环境的状态。

## global-status

```
vagrant global-status
```

显示当前登录用户系统上所有活动的 Vagrant 环境的状态

## halt

关闭正在运行的 vagrant 机器

```
vagrant halt [name|id]
```

## init 

初始化一个 Vagrantfile，将当前目录初始化为 vagrant 环境，

如果给出第一个参数，它将预先填充 Vagrantfile 中 `config.vm.box` 的设置。

如果给出第二个参数，它将预先填充 Vagrantfile 中 `config.vm.box_url` 的设置。


|选项 | 说明|
|---|---|
|-\-box-version| （可选）选定 box 的版本添加到 Vagrantfile|
|-\-force| 如果指定，则此命令将覆盖任何现有的 Vagrantfile|
|-\-minimal| 如果指定，将创建一个最小的 Vagrantfile。|
|-\-output FILE|这将输出 Vagrantfile 到给定的文件。如果这是 `-`，则 Vagrantfile 将被发送到标准输出。|
|-\-template FILE|提供用于生成 Vagrantfile 的自定义ERB模板。|

`vagrant init ` 例子

创建一个标准的 Vagrantfile：

```
$ vagrant init hashicorp/precise64

```

创建一个最小的 Vagrantfile（没有注释和帮助）：

```
$ vagrant init -m hashicorp/precise64
```

创建一个新的 Vagrantfile，覆盖当前的 Vagrantfile:

```
$ vagrant init -f hashicorp/precise64
```

使用指定的 url 创建一个 Vagrantfile：

```
$ vagrant init my-company-box https://boxes.company.com/my-company.box
```

创建一个 Vagrantfile，并且限制版本：

```
$ vagrant init --box-version '> 0.1.5' hashicorp/precise64
```


## package 

```
vagrant package [name|id]
```

将当前运行的 VirtualBox 或 Hyper-V 环境打包到可重复使用的 box 文件，

选项|说明
---|---
-\-base NAME |不是打包 Vagrant 管理的 VirtualBox 机器，而是打包 VirtualBox 管理的 VirtualBox 机器。 NAME 应该是 VirtualBox GUI 中机器的名称或UUID。目前该选项仅适用于 VirtualBox。
-\-output NAME| 生成的包将被保存为NAME。默认情况下，它将被保存为 package.box
-\-include x,y,z| 其他文件将随包装一起打包。这些可以被打包的Vagrantfile（下面记录）用来执行其他任务。
-\-vagrantfile FILE| 用框打包Vagrantfile，在 使用结果框时将其作为Vagrantfile加载次序的一部分加载。



## port

```
 vagrant port [name|id]
```

port命令显示映射到主机端口的访客端口的完整列表：

```
$ vagrant port
    22 (guest) => 2222 (host)
    80 (guest) => 8080 (host)
```

在多机Vagrantfile中，必须指定机器的名称：
```
$ vagrant port my-machine
```

## reload

```
 vagrant reload [name|id]
```

停止，并重新加载 Vagrantfile ，常用于更改配置之后，重新启动，载入配置


## Suspend

```
vagrant suspend [name|id]
```

暂停 Vagrant 正在管理的访客机器，而不是完全关闭或销毁它。

## Resume
```
vagrant resume [name|id]
```
恢复先前被挂起的流浪者管理的机器。

## Snapshot

```
vagrant snapshot
```

为 vagrant 虚拟机打快照，以便于以后恢复到某一状态。

**子命令**

子命令|说明
---|---
vagrant snapshot push|将当前虚拟机状态打成快照，并推送到快照栈
vagrant snapshot pop|恢复之前 push 的快照状态。并删除快照
vagrant snapshot save [vm-name] NAME|该命令保存一个新的命名快照。如果使用此命令， 则不能安全地使用 push 和 pop 子命令
vagrant snapshot restore [vm-name] NAME|该命令将恢复指定的快照。
vagrant snapshot list|列出所有拍摄的快照
vagrant snapshot delete NAME|删除命名的快照


## ssh

```
vagrant ssh [name|id] [-- extra_ssh_args]
```

这将SSH连接到正在运行的Vagrant机器，并允许您访问 SHELL 。

## status

```
vagrant status [name|id]
```

这会告诉你Vagrant正在管理的机器的状态


## up

```
vagrant up [name|id]
```

启动 vagrant 虚拟机


## vagrant 多台主机

在同一个项目 Vagrantfile 中定义多台机器 `config.vm.define` , 
```ruby
# -*- mode: ruby -*-
Vagrant.configure("2") do |config|
  config.vm.provision "shell", inline: "echo Hello"

  config.vm.define "web" do |web|
    web.vm.box = "centos/7"
    config.vm.network "public_network"
      config.vm.provider "virtualbox" do |vb|
        vb.memory = "2048"
      end
    end

  config.vm.define "db",autostart: false do |db|
    db.vm.box = "centos/7"
      config.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      end
    end

end
```

### 控制多台机器

当 Vagrantfile 中定义了多台机器时，各种 vagrant 命令的用法稍有变化。改变应该是直观的。

只有目标单个机器才有意义的命令，例如 `vagrant ssh`，现在需要机器的名称来控制。使用上面的例子，你会说 `vagrant ssh web` 或 `vagrant ssh db`。

其他命令（例如 `vagrant up`，默认情况下在每台机器上运行）。所以如果你跑了 vagrant up，Vagrant会同时启动 Web 和 DB 机器。你也可以指定启动的机器，使用 `vagrant up web` 或  `vagrant up db`。

此外，您可以指定一个正则表达式来仅匹配某些机器。这是在你指定许多类似的机器，例如，如果你正在测试一个分布式的服务你可能有一些情况下是有用 leader 的机器，以及 `follower0`，`follower1`，`follower2` 如果你想调出所有的追随者，但等不得的领导者，你可以做 `vagrant up /follower[0-9]/`。如果Vagrant 在正斜杠内看到一个机器名称，它假定您正在使用正则表达式。

### 网络
为了促进多机设置中机器间的通信，应使用各种网络选项。特别是，专用网络(`private network`) 可用于在多台机器和主机之间建立专用网络。

### 自启动

默认情况下，在多机环境中，vagrant up将启动所有定义的机器。该autostart设置允许您告诉Vagrant 不启动特定机器。例：
```
config.vm.define "web"
config.vm.define "db"
config.vm.define "db_follower", autostart: false
```


