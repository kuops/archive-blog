---
title: 使用 WSL 操作 Vagrant
date: 2018-05-02 16:20:20
categories: 
- vagrant
---

## 安装 VirtualBox

步骤略，VitrualBox 安装在 Windows 中

## 安装 Vagrant

Vagrant 必须安装在 Windows 的子系统 Ubuntu 中。即使使用 Win vagrant.exe 文件可以从WSL内部执行，它也不会按预期运行。要将 Vagrant 安装到 WSL 中，请按照下列步骤操作：

```
wget https://releases.hashicorp.com/vagrant/2.0.4/vagrant_2.0.4_x86_64.deb
sudo dpkg -i vagrant_2.0.4_x86_64.deb
```

## 使用 Vagrant

检查是否可以通过添加路径来运行 windows 的可执行文件:
```
export PATH=$PATH:/mnt/c/Windows/System32
```

然后尝试打开notepad.exe

Vagrant 在 WSL 中运行时会检查第三方可执行程序。例如，使用 VirtualBox 提供程序时，Vagrant 将与安装在 Windows 系统上的 VirtualBox 进行交互。确保所有必需的 Windows 可执行文件在您的内部都可 PATH 用以允许 Vagrant 访问它们，这一点非常重要。

```
sed -i '$a\export PATH="$PATH:/mnt/d/VirtualBox"' ~/.bashrc
source ~/.bashrc
```

## 访问 Windows

在 WSL 内部工作提供了一个与实际 Windows 系统隔离的层。在大多数情况下，Vagrant 需要访问实际的 Windows 系统才能正常运行。由于大多数 Vagrant 提供程序需要直接安装在 Windows 上（不在WSL内），因此 Vagrant 需要 Windows 访问权限。通过环境变量来控制对 Windows 系统的访问：VAGRANT_WSL_ENABLE_WINDOWS_ACCESS。如果设置了此环境变量，Vagrant将访问Windows系统以运行可执行文件并启用诸如同步文件夹之类的内容。在WSL中的bash shell中运行时，可以像这样设置环境变量：

```
sed -i '$a\export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"' ~/.bashrc
source ~/.bashrc
```

这将使Vagrant能够访问WSL之外的Windows系统，并与Windows可执行文件正确交互。VAGRANT_HOME 如果它尚未定义，它会自动修改环境变量，并将其设置为在Windows用户的主目录中。


请注意，与Windows系统共享的路径不会强制执行Linux权限。例如，当使用VirtualBox提供程序将WSL中的目录同步到guest虚拟机时，在该目录（或其内容）上定义的任何本地权限都不会从guest虚拟机可见。同样，从同步文件夹中的guest虚拟机创建的任何文件在WSL中都是世界可读/可写的。

其他有用的WSL相关环境变量：

- VAGRANT_WSL_WINDOWS_ACCESS_USER - 覆盖当前的Windows用户名
- VAGRANT_WSL_DISABLE_VAGRANT_HOME- 不要修改VAGRANT_HOME变量
- VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH - 自定义Windows系统主路径

```
sed -i '$a\export VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH=/mnt/d/' ~/.bashrc
sed -i '$a\export VAGRANT_HOME=/mnt/d/vagrant-home/.vagrant.d/' ~/.bashrc
source ~/.bashrc
```

如果 Vagrant项目目录不在 Windows 系统的用户主目录中，某些包含权限检查的操作可能会失败（如 vagrant ssh）。当访问 WSL Vagrant 之外的 Vagrant 项目时，如果项目路径位于VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH 环境变量中定义的路径内，则会跳过这些权限检查。例如，如果用户想要从位于以下位置的 WSL 运行 Vagrant 项目 C:\TestDir\vagrant-project：

## 启动 Vagrant

```
mkdir /mnt/d/vagrant-home/centos/
cd /mnt/d/vagrant-home/centos/
vagrant init centos/7
vagrant up
vagrant ssh
```


