---
title: Vagrant 和 VirtualBox 设置
date: 2018-05-14 03:56:20
categories:
- vagrant
---

## VirtualBox 设置 

### VM 存储位置和网络

管理 --> 菜单设定 --> 常规

![](/img/virtualbox/1.png)

### Nat 设置

管理 --> 菜单设定 --> 网络

![](/img/virtualbox/2.png)

### Private Network 设置

管理 --> 主机网络管理器，删除原有得网络，然后点击创建，配置网卡的 IP 地址：

![](/img/virtualbox/3.png)

配置 DHCP 服务的地址:

![](/img/virtualbox/4.png)


## Vagrant 设置

### Vagrant 初始化

生成 Vagrantfile，并启动 Vagrant
```
vagrant init centos/7
vagrant up
```

### 自定义基础 box

可以 `vagrant ssh` 登陆进去，并安装常用软件，设置内核参数等。
```
vagrant ssh
yum -y install wget
```
安装完成之后，导出 box 文件
```
vagrant global-status
vagrant package 367a518 --output mycentos7.box
```
添加导出的文件到 box 仓库
```
vagrant box add --name mycentos/7 mycentos7.box
vagrant box list
```

### 创建虚拟机

基于已经创建的 box 镜像创建虚拟机
```
mkdir mycentos
cd  mycentos/
vagrant init mycentos/7
vagrant up
```

修改 vagrantfile
```
# -*- mode: ruby -*-
Vagrant.configure("2") do |config|

  config.vm.define "node1" do |node1|
    node1.vm.box = "mycentos/7"
    config.vm.synced_folder "/mnt/d/vagrant-home/mycentos", "/vagrant" , type: "rsync"
    config.vm.network "private_network", ip: "10.0.7.100"
      config.vm.provider "virtualbox" do |vb|
        vb.memory = "1024"
    end
  end

  config.vm.define "node2" do |node2|
   node2.vm.box = "mycentos/7"
    config.vm.synced_folder "/mnt/d/vagrant-home/mycentos", "/vagrant" , type: "rsync"
    config.vm.network "private_network", ip: "10.0.7.101"
      config.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
    end
  end

end
```

启动
```
vagrant up
vagrant ssh node1
vagrant ssh node2
```


