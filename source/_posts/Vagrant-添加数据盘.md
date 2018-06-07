---
title: Vagrant 添加数据盘
date: 2018-06-07 15:10:09
categories:
- vagrant
---

## 添加数据盘

查询当前 vm 使用的硬盘控制器
```
kuops@kuops:/mnt/d/vagrant-home/test$ VBoxManage.exe list vms
"test_default_1528203161003_69396" {c9399b22-e486-4729-bcc9-0f1767ea3542}


kuops@kuops:/mnt/d/vagrant-home/test$ VBoxManage.exe showvminfo c9399b22-e486-4729-bcc9-0f1767ea3542|grep -i 'storage'
Storage Controller Name (0):            IDE
Storage Controller Type (0):            PIIX4
Storage Controller Instance Number (0): 0
Storage Controller Max Port Count (0):  2
Storage Controller Port Count (0):      2
Storage Controller Bootable (0):        on
```

看到当前使用的 Controller Name 为 IDE, Vagrantfile 修改如下

```
# -*- mode: ruby -*-
# vi: set ft=ruby :

file_to_disk = './tmp/large_disk.vdi'

Vagrant.configure("2") do |config|
  config.vm.box = 'centos/7'
  config.vm.provider "virtualbox" do |vb|
    if !File.exist?(file_to_disk)
      # 100 * 1024M = 100G
      vb.customize ['createhd', '--filename', file_to_disk, '--size', 100 * 1024]
    end
    vb.customize ['storageattach', :id, '--storagectl', 'IDE', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', file_to_disk]
  end

  config.vm.provision "shell", inline: <<-SHELL
set -e
set -x

if [ -f /etc/default/disk-format ]
then
   echo "disk is formated."
   exit 0
fi

sudo fdisk -u /dev/sdb <<EOF
n
p
1


w
EOF

mkfs.xfs /dev/sdb1
mkdir -p /data
mount -t xfs /dev/sdb1 /data && sudo echo "/dev/sdb1 xfs        /data    defaults        0 0" >> /etc/fstab

date > /etc/default/disk-format
  SHELL

  config.vm.provision "shell", inline: <<-SHELL
    echo "deploy done"
  SHELL
end
```
如果出现如下报错，证明 controller 不存在，
```
A customization command failed:

["storageattach", :id, "--storagectl", "IDE Controller", "--port", 0, "--device", 1, "--type", "hdd", "--medium", "sdb.vdi"]

The following error was experienced:

#<Vagrant::Errors::VBoxManageError: There was an error while executing `VBoxManage`, a CLI used    by Vagrant
for controlling VirtualBox. The command and stderr is shown below.

Command: ["storageattach", "4d543d7e-1183-4123-9b6b-c8751901adb2", "--storagectl", "IDE Controller", "--port", "0", "--device", "1", "--type", "hdd", "--medium", "sdb.vdi"]

Stderr: VBoxManage: error: Could not find a controller named 'IDE Controller'
>

Please fix this customization and try again.
```
在某些版本中 controller 需要写全名 `IDE Controller`，查询方法下如下
```
cat ../.vagrant.d/boxes/centos-VAGRANTSLASH-7/0/virtualbox/box.ovf |grep -i "storagecontroller"
```

如果出现如下错误，则表示 vdi 存储已存在，需要清理掉已创建的磁盘，并重新创建
```
A customization command failed:

["createhd", "--filename", "./tmp/large_disk.vdi", "--size", 512000]

The following error was experienced:

#<Vagrant::Errors::VBoxManageError: There was an error while executing `VBoxManage`, a CLI used by Vagrant
for controlling VirtualBox. The command and stderr is shown below.

Command: ["createhd", "--filename", "./tmp/large_disk.vdi", "--size", "512000"]

Stderr: 0%...
Progress state: VBOX_E_FILE_ERROR
VBoxManage.exe: error: Failed to create medium
VBoxManage.exe: error: Could not create the medium storage unit 'D:\vagrant-home\test\tmp\large_disk.vdi'.
VBoxManage.exe: error: VDI: cannot create image 'D:\vagrant-home\test\tmp\large_disk.vdi' (VERR_ALREADY_EXISTS)
VBoxManage.exe: error: Details: code VBOX_E_FILE_ERROR (0x80bb0004), component MediumWrap, interface IMedium
VBoxManage.exe: error: Context: "enum RTEXITCODE __cdecl handleCreateMedium(struct HandlerArg *)" at line 450 of file VBoxManageDisk.cpp
>

Please fix this customization and try again.
```
清理命令如下
```
vagrant destroy -f
rm -f /tmp/*.vdi
```
