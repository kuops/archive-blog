---
title: Linux 的 CGroup 和 Namespace
date: 2019-01-24 00:35:00
tags:
categories:
- docker
---


## Chroot

在类 Unix 操作系统中，根目录(root directory) `/` 是顶级目录，所有文件系统的路径都是从跟 `/` 开始，使用 Chroot 可以更改进程及子进程识别到的根目录 `/` 改为其他目录。


开始一个 chroot 例子,创建一个只有 bash 和 ls 的目录
```
mkdir -p $HOME/chroot-test/{bin,lib64}
cp $(which --skip-alias ls) $HOME/chroot-test/bin
cp $(which --skip-alias bash) $HOME/chroot-test/bin
ldd $(which --skip-alias ls)|grep -Po '/lib64/\S+'|xargs -i cp {} $HOME/chroot-test/lib64
ldd $(which --skip-alias bash)|grep -Po '/lib64/\S+'|xargs -i cp {} $HOME/chroot-test/lib64
```

切换到该目录，发现改根目录已经更改：
```
~]$ sudo chroot $HOME/chroot-test /bin/bash
bash-4.2# ls /
bin  lib64
```

查看进程中的变化：

```
#查到下面的 16899 的进程是由 16891 进程创建
~]$ ps -ef|grep bash
root     16891 24867  0 15:19 pts/0    00:00:00 sudo chroot /home/vagrant/chroot-test /bin/bash
root     16899 16891  0 15:19 pts/0    00:00:00 /bin/bash

#查看进程的 root 已经被替换
 ~]$ sudo ls -l /proc/16899/root
lrwxrwxrwx 1 root root 0 Jan 23 15:22 /proc/16899/root -> /home/vagrant/chroot-test

#查看父进程的，因为 chroot 只针对创建出来的子进程生效，所以父进程还是真正的根
 ~]$ sudo ls -l /proc/16891/root
lrwxrwxrwx 1 root root 0 Jan 23 15:23 /proc/16891/root -> /
```

## NameSpace

Linux 的进程都是单一树状结构，所有的进程都是从 `init` 进程开始，通常特权进程可以跟踪或杀死其他的普通进程。Linux 的 NameSpace 将分出多个 `subtree` 子树结构，将进程隔离开来。

Mount Namespace 在 2.4.19 内核中出现，用于运行时隔离的 Namespace 。在 4.7.1 内核中已经又 7 种不同类型的 Namespace 类型。

```
~]# uname -r
4.10.4-1.el7.elrepo.x86_64

~]# ls -l /proc/1076/ns
总用量 0
lrwxrwxrwx 1 root root 0 1月  23 02:42 cgroup -> cgroup:[4026531835]
lrwxrwxrwx 1 root root 0 1月  23 02:42 ipc -> ipc:[4026531839]
lrwxrwxrwx 1 root root 0 1月  23 02:42 mnt -> mnt:[4026531840]
lrwxrwxrwx 1 root root 0 1月  23 02:42 net -> net:[4026531957]
lrwxrwxrwx 1 root root 0 1月  23 02:42 pid -> pid:[4026531836]
lrwxrwxrwx 1 root root 0 1月  23 02:42 user -> user:[4026531837]
lrwxrwxrwx 1 root root 0 1月  23 02:42 uts -> uts:[4026531838]
```

每个进程都具有这 7 个属性，因此每个进程都会分别在这些 Namespace 控制的系统资源上与另一些进程共享空间。在没有使用容器的情况下，系统中所有进程都具有相同的 Namespace ID 组合，如果一个进程运行在 Docker 容器里，他就很可能有一组完全不同的一组 Namespce ID，也可以只做部分隔离，例如使用了 `--network=host`, net Namespace的ID 就会和宿主机的 ID 相同。

- Cgroup Namespace： 提供基于 CGroup （控制组） 的隔离能力。 CGroup 是 Linux 在内核级别对进程可用资源进行限制的一组规则， CGroup 的隔离能让不同的进程组看到不同的 CGroup 规则， 为不同进程组采用各自的配额标准提供便利。

- IPC Namespace：提供基于 system V 进程信道的隔离能力。IPC 全称 Inter-Process Communication， 是 Linux 中的一种标准的进程间通信方式， 包括共享内存，信号量，消息队列等具体方法。IPC 隔离使得只有在同一命名空间下的进程才能相互通信，这一特性对于消除不同容器空间中进程的相互影响具有十分重要的作用。

- Mount Namespace： 提供基于磁盘挂载和文件系统的隔离能力。这种隔离效果和 chroot 十分相似，这种效果与 chroot 十分相似，但从实际原理看，mount namespace 会为隔离空间创建独立的 mount 节点树，而 chroot 只改变了当前上下位的根节点 mount 的位置，在文件系统隔离的情况下，无法访问到容器外的任何文件，可以配置挂在额外的目录访问到宿主机的文件系统。

- Network Namespace： 提供基于网络栈的隔离能力，网络栈的隔离允许使用者将特定的网卡与特定容器中的进程进行上下文关联起来，使得同一网卡在主机和容器中分别呈现不同的名称。Network Namespace 的重要作用之一就是让每个容器通过命名空间来隔离和管理自己的网卡配置。因此可以创建一个普通的虚拟网卡，并将它作为特定容器运行环境的默认网卡 eth0 使用。这些虚拟网络网卡最终可以通过某些方式(NAT,VXLAN,SDN 等)，连接到实际的物理网卡上，从而实现像普遍主机一样的网络通信。

- PID Namespace： 提供基于进程的隔离能力。进程隔离使得容器中的首个进程成为所在命名空间中的 PID 为 1 的进程。在 Linux 系统中， PID 为 1 的进程非常特殊，它作为所有进程的父进程，有很多特权，如，屏蔽信号，托管孤儿进程等。一个比较直观的现象是，当系统中的某个子进程脱离了父进程（例如父进程意外结束），那么它的父进程就会自动成为系统的根父进程。此外，当系统中的根父进程退出时，所有属于同一命名空间的进程都会被杀死。

- User Namespace：提供基于系统用户的隔离能力。系统用户隔离是指同一系统用户在不同命名空间中拥有不同的 UID （用户标识） 和 GID （组标识）。他们之间存在一定的映射关系。因此在特定的命名空间中 UID 为 0 并不表示该用用拥有整个系统的管理员 root 用户的权限。这一特性限制了容器的用户权限，有利于保护主机系统的安全。

- UTS Namespace： 提供基于主机名的隔离能力。在每个独立的命名空间中，程序都可以有不同的主机名称信息。值得一提的时，主机名只是一个用于标识容器空间的代号，允许重复。



Linux 提供以下 API 用来管理命名空间：

*   clone() – 普通 clone() 会创建一个新进程。如果我们将一个或多个 `CLONE_NEW*` 标志传递给 clone（），则会为每个标志创建新的命名空间，并使子进程成为这些命名空间的成员。

*   unshare() – 使某进程脱离某个namespace

*   setns() – 允许一个进程加入已存在的命名空间。namspace 由 `proc/[pid]/ns` 中文件的文件描述符指定。


## Cgroup

CGroup 是 Linux 内核提供的一种可以限制，记录，隔离一组进程所使用的物理资源的机制（包括 CPU , 内存，磁盘 I/O 速度）机制。

CGroup 最初设计出来是为了统一 Linux 下资源管理工具，比如限制 CPU 时使用的 `renice` 和 `cpulimit` 命令，限制内存要用 ulimit 或者 PAM (pluggable Authentication Modules),而限制磁盘 I/O 又需要其他工具。CGroup 是一种内核级的限制手段，比其他的要的功能和效率方便好得多。CGroup 在 systemd 的 service 文件定义中 `MemoryLimit`,`BlockIOWeight` 等配置其实就是在间接的为进程配置 CGroup。


查看进程的 cgroup 文件，

```
~]# ls  -l /proc/1076/cgroup
-r--r--r-- 1 root root 0 1月  23 02:42 /proc/1076/cgroup
[root@host ~]# cat /proc/1076/cgroup
11:freezer:/
10:cpu,cpuacct:/system.slice/sshd.service
9:hugetlb:/
8:net_cls,net_prio:/
7:devices:/system.slice/sshd.service
6:cpuset:/
5:pids:/
4:blkio:/system.slice/sshd.service
3:perf_event:/
2:memory:/system.slice/sshd.service
1:name=systemd:/system.slice/sshd.service
```

除了最后一行，都对应一个 CGroup 的子系统，每个子系统用于定义某个资源的控制规则的结构。

查看一个运行在容器中的进程的 CGroup，和其他进程的路径完全不同:
```
 ~]# cat /proc/11668/cgroup
11:freezer:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
10:cpu,cpuacct:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
9:hugetlb:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
8:net_cls,net_prio:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
7:devices:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
6:cpuset:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
5:pids:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
4:blkio:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
3:perf_event:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
2:memory:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
1:name=systemd:/docker/72c668d48c34a6c2b449d6a228e91b3c0bf3b6ee2806eb0a98ae444ae3f4e551
```

查看 mount 的挂载点：

```
~]# mount|grep 'cgroup'
tmpfs on /sys/fs/cgroup type tmpfs (ro,nosuid,nodev,noexec,mode=755)
cgroup on /sys/fs/cgroup/systemd type cgroup (rw,nosuid,nodev,noexec,relatime,xattr,release_agent=/usr/lib/systemd/systemd-cgroups-agent,name=systemd)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)
cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)
cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)
cgroup on /sys/fs/cgroup/net_cls,net_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net_cls,net_prio)
cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)
cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpu,cpuacct)
cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)
```

这里每个挂载点都是一个 CGroup 子系统的根目录，例如 `cpuset:/` 对应的根目录其实是 `/sys/fs/cgroup/cpuset`,其他的以此类推。

常见的 CGroup 如下：

- hubetlb  用于限制进程对大页内存(Hugpage) 的使用

- memory 用于限制对内存和 swap 的使用，并生成每个进程使用的资源报告。

- pids 子系统用于限制每个 CGroup 中能创建的进程总数。

- cpuset 在多核系统中为进程分配独立的 CPU 和内存。

- devices 允许或者拒绝 cgroup 中的进程访问指定设备。

- net_cls 和 net_prio 子系统用于标记每个网络包，并控制网卡的优先级。

- cpu 和 cpuacct 用于限制进程对 CPU 的用量，并生成每个进程所使用的 CPU 报告。

- freezer 可以挂起或恢复特定的进程。

- blkio 用于进程对块设备(磁盘 USB 等)限制输入输出。

- perf_event 可以检测属于特定的 CGroup 的所有线程及运行在特定 CPU 上的线程。

我们可以使用 CGroup Tools 来对 cgroup 进行设置

```
# ubuntu
apt-get install cgroup-tools
# or centos
yum -y install libcgroup-tools
```

这个工具包含了一组用于创建和修改 CGroup 信息的命令，通过 cgcreate 创建两个 CGroup 的子分组, `-g cpu` 表示设定的是 CPU  子系统的配额，同样也可以设置其他配额的子系统。 通过 lscgroup 可以查看到这两个子系统

```
cgcreate -g cpu:/cpu50
cgcreate -g cpu:/cpu30

# 查看创建的 cgroup
~]# lscgroup |grep cpu[35]0
cpu,cpuacct:/cpu50
cpu,cpuacct:/cpu30

]# ls -ld /sys/fs/cgroup/cpu,cpuacct/cpu[35]0
drwxr-xr-x 2 root root 0 1月  23 08:44 /sys/fs/cgroup/cpu,cpuacct/cpu30
drwxr-xr-x 2 root root 0 1月  23 08:44 /sys/fs/cgroup/cpu,cpuacct/cpu50
```

为两个 CPU 分组设置一条限制规则， CPU 的子系统的 `cfs_quota_us` 可以设定进程在每个时间片周期内可占用的最大 CPU 时间， 单位是 `μs`，CPU 的时间片周期由子系统的 cfs_period_us 属性指定，默认为 100000, 单位同样是 `μs`,因此 cfs_quota_us 的数值 50000 和 30000 表示改组中的进程最多分别能够使用 50% 和 30% 的 CPU 时间。 使用 cgset 将规则设定进两个分组中。

```
cgset -r cpu.cfs_quota_us=50000 cpu50
cgset -r cpu.cfs_quota_us=30000 cpu30

]# cat /sys/fs/cgroup/cpu,cpuacct/cpu30/cpu.cfs_quota_us
30000
]# cat /sys/fs/cgroup/cpu,cpuacct/cpu50/cpu.cfs_quota_us
50000
```

测试 CPU 使用

```
yum -y install stress
stress -c 1 --timeout 360s >  /dev/null &
```

此时查看 cpu 使用率
```
~]# ps aux|grep stress
root     13112 99.0  0.0   7264    92 pts/0    R    09:41   0:48 stress -c 1 --timeout 360s
```

使用 cgexec 命令将 stress 进程切换到 cpu50 CGroup 中重新运行

```
cgexec -g cpu:cpu50 stress -c 1 --timeout 360s > /dev/null &

~]# ps aux|grep stress
root     13122 49.9  0.0   7264    96 pts/0    R    09:45   0:15 stress -c 1 --timeout 360s
```

查看该进程的 cgroup ,cpu 使用 cpu50 CGroup

```
~]# cat /proc/13122/cgroup
11:freezer:/
10:cpu,cpuacct:/cpu50
9:hugetlb:/
8:net_cls,net_prio:/
7:devices:/user.slice
6:cpuset:/
5:pids:/
4:blkio:/user.slice
3:perf_event:/
2:memory:/user.slice
1:name=systemd:/user.slice/user-0.slice/session-1076.scope
```

再启动一个进程,可以看到使用的再同一 CGroup 中使用的最大 CPU 加起来也是差不多 50%
```
cgexec -g cpu:cpu50 stress -c 1 --timeout 360s > /dev/null &

ps aux --sort=-%cpu|head -3
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root     13131 26.5  0.0   7264    96 pts/0    R    09:48   1:00 stress -c 1 --timeout 360s
root     13181 23.5  0.0   7264    92 pts/0    R    09:52   0:01 stress -c 1 --timeout 360s
```

使用 CPU30 子系统, 每个 10%

```
cgexec -g cpu:cpu30 stress -c 1 --timeout 360s > /dev/null &
cgexec -g cpu:cpu30 stress -c 1 --timeout 360s > /dev/null &
cgexec -g cpu:cpu30 stress -c 1 --timeout 360s > /dev/null &

~]# ps aux --sort=-%cpu|head -4
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root     13201  9.9  0.0   7264    96 pts/0    R    10:22   0:01 stress -c 1 --timeout 360s
root     13199  9.8  0.0   7264    96 pts/0    R    10:22   0:01 stress -c 1 --timeout 360s
root     13203  9.5  0.0   7264    96 pts/0    R    10:22   0:01 stress -c 1 --timeout 360s
```

本质上使用 CGroup 的操作就是对进程挂在的 CGroup 目录

```
~]# cat /proc/13212/cgroup
11:freezer:/
10:cpu,cpuacct:/cpu30
9:hugetlb:/
8:net_cls,net_prio:/
7:devices:/user.slice
6:cpuset:/
5:pids:/
4:blkio:/user.slice
3:perf_event:/
2:memory:/user.slice
1:name=systemd:/user.slice/user-0.slice/session-1076.scope

~]# cat /sys/fs/cgroup/cpu,cpuacct/cpu30/tasks
13212
13213
```

不使用 cgroup-tools 手动操作:
```
mkdir /sys/fs/cgroup/cpu/cpu20
~]# ls  -l /sys/fs/cgroup/cpu/cpu20
总用量 0
-rw-r--r-- 1 root root 0 1月  23 10:38 cgroup.clone_children
-rw-r--r-- 1 root root 0 1月  23 10:38 cgroup.procs
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.stat
-rw-r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_all
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_percpu
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_percpu_sys
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_percpu_user
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_sys
-r--r--r-- 1 root root 0 1月  23 10:38 cpuacct.usage_user
-rw-r--r-- 1 root root 0 1月  23 10:38 cpu.cfs_period_us
-rw-r--r-- 1 root root 0 1月  23 10:38 cpu.cfs_quota_us
-rw-r--r-- 1 root root 0 1月  23 10:38 cpu.rt_period_us
-rw-r--r-- 1 root root 0 1月  23 10:38 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 1月  23 10:38 cpu.shares
-r--r--r-- 1 root root 0 1月  23 10:38 cpu.stat
-rw-r--r-- 1 root root 0 1月  23 10:38 notify_on_release
-rw-r--r-- 1 root root 0 1月  23 10:38 tasks

echo 20000 > /sys/fs/cgroup/cpu/cpu20/cpu.cfs_quota_us
stress -c 1 --timeout 360s > /dev/null &
echo $! >> /sys/fs/cgroup/cpu/cpu20/tasks
```
> 由于 "/sys/fs/cgroup/cpu" 目录被挂在为 CGroup 类型的文件系统，当用户再改目录创建子目录时，会自动创建所需的结构文件



