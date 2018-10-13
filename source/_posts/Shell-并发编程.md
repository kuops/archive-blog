---
title: 创建 Kubernetes 集群：环境准备
date: 2018-07-19 13:31:40
tags:
categories:
- Shell
---

## SHELL 重定向

Linux 系统将所有设备都当作文件来处理，而 Linux 用文件描述符来标识每个文件对象。其实我们可以想象我们电脑的显示器和键盘在 Linux 系统中都被看作是文件，而它们都有相应的文件描述符与之对应。

Linux shell 使用 3 种标准的 I/O 流，每种流都与一个文件描述符相关联：

1. `stdout` 是标准输出流，它显示来自命令的输出。它的文件描述符为 1。
2. `stderr` 是标准错误流，它显示来自命令的错误输出。它的文件描述符为 2。
3. `stdin` 是标准输入流，它为命令提供输入。它的文件描述符为 0。

|重定向 | 作用|
|---|---|
|cmd > file|将命令输出重定向到文件|
|cmd 1> file|和 cmd > file 相同，重定向到标准输出 |
|cmd 2> file|将标准错误重定向到文件|
|cmd >> file|将标准输出追加到文件|
|cmd 2>> file|将标准错误追加到文件|
|cmd &> file|将标准输出和标准错误追加到文件|
|cmd > file 2>&1|将标准输出和标准错误追加到文件和 cmd &> file 相同 |
|cmd > /dev/null|丢掉标准输出|
|cmd 2> /dev/null|丢掉标准错误|
|cmd &> /dev/null|丢掉标准错误和标准输出|
|cmd < file| 将文件作为命令的标准输入|
|cmd << EOF </br>foo</br>bar</br>EOF|将多行文本作为命令的标准输入|
|cmd << EOF </br>&lt;tab&gt;foo</br>&lt;tab&gt;bar</br>EOF|将多行文本作为命令的标准输入,忽略 tab 键 |
|cmd <<< "string"|将单行文本作为命令的标准输入|
|exec 2> file|将所有命令的标准错误重定向到文件|
|exec 3< file|使用自定义文件描述符打开文件进行读操作|
|exec 3> file|使用自定义文件描述符打开文件进行写操作|
|exec 3<> file|使用自定义文件描述符打开文件同时进行读写操作|
|exec 3>&-|关闭文件描述符|
|exec 4>&3|创建文件描述符4，并将 3 的内容复制给 4|
|exec 4>&3-|创建文件描述符4，并将 3 的内容复制给 4，并且关闭 3|
|echo "foo" >&3|将 foo 写入文件描述符 3|
|cat <&3|从文件描述符中读取数据|
|(cmd1; cmd2) > file|将多个命令结果重定向到文件，使用子 shell|
|{ cmd1; cmd2; } > file|将多个命令结果重定向到文件，使用当前shell|

## SHELL 管道

### 匿名管道

在 Unix 或类 Unix操 作系统的命令行中，匿名管道使用ASCII中垂直线`|`作为匿名管道符，匿名管道的两端是两个普通的，匿名的，打开的文件描述符：一个**只读端**和一个**只写端**，这就让其它进程无法连接到该匿名管道。

例如：

```
seq 10|head
```

将 `seq 10` 的标准输出（文件描述符为`fd 1`）作为 head 命令的标准输入 （文件描述符为`fd 0`），这两个进程同时执行，它们只是从标准文件描述符中读取数据和写入数据。


### 命名管道 (Named Pipe)

命名管道也称 FIFO，从语义上来讲，FIFO 其实与匿名管道类似，但值得注意：

- 在文件系统中，FIFO 拥有名称，并且是以设备特俗文件的形式存在的；
- 任何进程都可以通过 FIFO 共享数据；
- 除非 FIFO 两端同时有读与写的进程，否则 FIFO 的数据流通将会阻塞；
- 匿名管道是由 shell 自动创建的，存在于内核中；而 FIFO 则是由程序创建的（比如mkfifo命令），存在于文件系统中；
- 匿名管道是单向的字节流，而FIFO则是双向的字节流；



## SHELL 并发编程

首先，查看系统的描述符：

```
kuops@kuops:~$ ls -l /dev/fd/
total 0
lrwx------ 1 kuops kuops 0 Oct 13 13:04 0 -> /dev/pts/0
lrwx------ 1 kuops kuops 0 Oct 13 13:04 1 -> /dev/pts/0
lrwx------ 1 kuops kuops 0 Oct 13 13:04 2 -> /dev/pts/0
lr-x------ 1 kuops kuops 0 Oct 13 13:04 3 -> /proc/32/fd
```

我们可以看到系统的标准输入`0`,标准输出`1`,标准错误`2`，都已经在使用了，那 3 是什么呢？

```
ls -l /dev/fd/ &
```

我们可以使用上面的命令将 ls 放到后台执行，`echo $!` 获取 pid ，发现这个 3 就是当前执行 ls 的文件描述符。


将当前 shell 标准输出重定向到文件中，之后执行 ls pwd 发现并没有输出到标准输出
```
exec 1> file
ls
pwd
```

我们来查看一下 file 中的内容,我们看到刚刚的标准输出内容存储到 file 文件中了：

```
#将标准输出的东西返回给标准输入
exec 1>& 0

#查看 file 文件内容
:~$ cat file
devops
file
gitbook
go
/home/kuops
```

我们来自己定义一个文件描述符使用，文件描述符的数量取决于 `ulimit -n` 的值

```
#查看 limit 值
~$ ulimit -n
1024

#打开文件描述符1000，对其进行写操作，将描述符 1000 的数据写入 1000-fd-file
exec 1000> 1000-fd-file


#查看 fd
~$ ls -l /dev/fd/
total 0
lrwx------ 1 kuops kuops 0 Oct 13 13:45 0 -> /dev/pts/1
lrwx------ 1 kuops kuops 0 Oct 13 13:45 1 -> /dev/pts/1
l-wx------ 1 kuops kuops 0 Oct 13 13:45 1000 -> /home/kuops/1000-fd-file
lrwx------ 1 kuops kuops 0 Oct 13 13:45 2 -> /dev/pts/1
lr-x------ 1 kuops kuops 0 Oct 13 13:45 3 -> /proc/208/fd

#写入数据，将标准输出 `1` 的数据传给描述符 1000，
echo "hehe" 1>& 1000

#由于 1000 使用的是普通文件 1000-fd-file， 查看数据，已经传给了该描述符
~$ cat /home/kuops/1000-fd-file
hehe

#关闭描述符
exec 1000>&-
```

我们再来看下管道文件

```
#创建管道文件
mkfifo fifofile

#查看属性
~$ ls -l fifofile
prw-r--r-- 1 kuops kuops 0 Oct 13 13:51 fifofile
```

我们向管道发送一条数据,当我们执行完毕之后发现进程处于阻塞状态，因为信息没有被取出

```
~$ echo "Hello" > fifofile
```

我们新建终端,执行 cat 操作，由于管道中内容已被读出,阻塞的进程退出

```
:~$ cat fifofile
```


了解了这些，我们看下并发编程控制

```
#!/bin/bash

# 创建管道文件
mkfifo fifofile

# 创建文件描述符 1000 ，以读写方式操作管道文件 fifofile
exec 1000<> fifofile

# 删除管道文件 fifofile
rm fifofile

# 4 为并发进程数，生成 4 行数据，交给文件描述符，此时管道文件中也会有 4 行数据
seq 1 4 1>& 1000

for i in `seq 1 24`;do

#read -u 从文件描述符中读取数据，每次读取一行，管道中减少一行，当读完设置的 4行数据之后，再次读取进入阻塞状态，限制进程数量
  read -u 1000
  {
    # 要执行的一组任务，在花括号中，
    echo "success progress $i";
    # 为了测试效果 sleep
    sleep 2;
    # 当任务执行完毕之后往描述符中插入一个空行，保持管道中占位行一直为 4 行
    echo >& 1000
  } & # & 存放在后台执行，每循环一次，管道中的行 -1
done

#等待所有进程完成，最后退出
wait

# 关闭文件描述符写
exec 1000>&-
# 关闭文件描述符读
exec 1000<&-
```

> 为什么使用管道文件而不使用普通文件，因为管道中的数据只能读取一次，读取完成之后不可重复读取，等待没有可以读取的数据时，进入阻塞状态，利用此方法来控制并发。

> 为什么使用描述符 fd 来操作管道文件，而不是直接操作管道文件，因为如果直接操作管道文件，需要读写同时存在，而绑定文件描述符，则可以分开操作读写。







