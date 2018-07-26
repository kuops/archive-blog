---
title: 创建 Kubernetes 集群：环境准备
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第一部分`
1.  [环境准备](https://kuops.com/2018/07/19/deploy-kubernets-ha-01/)
2.  [生成证书](https://kuops.com/2018/07/19/deploy-kubernets-ha-02/)
3.  [生成kubeconfig](https://kuops.com/2018/07/19/deploy-kubernets-ha-03/)
4.  [配置 etcd 集群](https://kuops.com/2018/07/19/deploy-kubernets-ha-04/)
5.  [配置 HA](https://kuops.com/2018/07/19/deploy-kubernets-ha-05/)
6.  [配置 Master 组件](https://kuops.com/2018/07/19/deploy-kubernets-ha-06/)
7.  [配置 bootstrap](https://kuops.com/2018/07/19/deploy-kubernets-ha-07/)
8.  [配置 kubelet 组件](https://kuops.com/2018/07/19/deploy-kubernets-ha-08/)
9.  [配置 kube-proxy 组件](https://kuops.com/2018/07/19/deploy-kubernets-ha-09/)
10.  [配置 Flannel 和 CoreDNS](https://kuops.com/2018/07/19/deploy-kubernets-ha-10/)
11.  [配置 ipvs](https://kuops.com/2018/07/19/deploy-kubernets-ha-11/)
12.  [配置 traefik ingress](https://kuops.com/2018/07/19/deploy-kubernets-ha-12/)
13.  [配置 dashboard](https://kuops.com/2018/07/19/deploy-kubernets-ha-13/)
14.  [配置 promethus-opreater](https://kuops.com/2018/07/19/deploy-kubernets-ha-14/)
15.  [配置 EFK](https://kuops.com/2018/07/19/deploy-kubernets-ha-15/)
16.  [配置 Ceph 存储](https://kuops.com/2018/07/19/deploy-kubernets-ha-16/)



## 环境说明

本次部署使用 Vagrant 快速初始化环境。共有四台机器，三台主节点，一台工作节点

**环境列表如下:**

|IP|hostname|os|role|vip|
|---|---|---|
|10.0.7.101|k8s-master1|centos7|master|10.0.7.100|
|10.0.7.102|k8s-master2|centos7|master|10.0.7.100|
|10.0.7.103|k8s-master3|centos7|master|10.0.7.100|
|10.0.7.104|k8s-node1|centos7|worker|无|

vagrant 需要安装以下插件,vagrant-hostmanager 可以自动添加 /etc/hosts 文件

```
$ vagrant plugin list
vagrant-hostmanager (1.8.9)
```

通过 vagrant 配置文件文件，来快速初始化节点

```
# -*- mode: ruby -*-
# vi: set ft=ruby :

cluster = {
  "k8s-master1" => { :ip => "10.0.7.101", :disk => "./disk/k8s-master1.vdi", :mem => 2048 },
  "k8s-master2" => { :ip => "10.0.7.102", :disk => "./disk/k8s-master2.vdi", :mem => 2048 },
  "k8s-master3" => { :ip => "10.0.7.103", :disk => "./disk/k8s-master3.vdi", :mem => 2048 },
  "k8s-node1" => { :ip => "10.0.7.104", :disk => "./disk/k8s-node1.vdi", :mem => 16384 },
}

Vagrant.configure("2") do |config|
  config.vm.box = 'centos/7'
  #config.ssh.username = 'root'
  #config.ssh.password = 'vagrant'
  #config.ssh.insert_key = false
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  config.hostmanager.manage_guest = true
  config.hostmanager.ignore_private_ip = false
  config.hostmanager.include_offline = true
  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    #v.customize ["modifyvm", :id, '--natdnshostresolver1', 'on']
    #v.memory = 2048
    v.cpus = 2
  end

  cluster.each_with_index do |(hostname, info), index|
    config.vm.define hostname do |cfg|
      cfg.vm.provider :virtualbox do |vb, override|
        override.vm.network :private_network, ip: "#{info[:ip]}"
        override.vm.hostname = hostname
        vb.name = hostname
        if !File.exist?(info[:disk])
          vb.customize ['createhd', '--filename', info[:disk], '--size', 100 * 1024]
        end
        vb.customize ['storageattach', :id, '--storagectl', 'IDE', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', info[:disk]]
        vb.customize ["modifyvm", :id, "--memory", info[:mem], "--hwvirtex", "on"]
      end # end provider
    end # end config
  end # end cluster

  config.vm.provision "shell", inline: <<-SHELL
    #设置 root 密码，随自己习惯
    sed  -i 's@^PasswordAuthentication no@PasswordAuthentication yes@g' /etc/ssh/sshd_config
    systemctl restart sshd
    echo "root"|passwd --stdin root
    #安装常用软件，ipvsadm 使用 ipvs 模式时使用
    yum -y install wget
    wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
    wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
    yum -y install vim net-tools lrzsz bash-completion rsync sysstat git chrony tree yum-utils lsof zip unzip telnet nc ipvsadm
    sed -ri 's@^(SELINUX=).*@\1disabled@g' /etc/selinux/config
    #设置内核参数
    tee -a /etc/sysctl.d/kubernetes.conf << EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
EOF

    sysctl --system

# 安装 docker
curl -sSL https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo >  /etc/yum.repos.d/docker-ce.repo
yum -y install docker-ce conntrack-tools
mkdir -p /etc/docker/
cat <<'EOF'> /etc/docker/daemon.json
{
  "registry-mirrors": ["https://fz5yth0r.mirror.aliyuncs.com"],
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

    systemctl start docker
    systemctl enable docker
    usermod -G docker vagrant

#关闭swap分区
swapoff -a
sed -i 's@.*swap.*@#&@g' /etc/fstab

#选择需要开机加载的内核模块，以下是 ipvs 模式需要加载的模块
cat <<EOF> /etc/modules-load.d/ipvs.conf
#auto load ipvs
ip_vs
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack_ipv4
EOF
#重新加载内核模块，这个 unit 文件是一次性的，每次设置完毕需要安装的模块，重新加载即可
systemctl start systemd-modules-load.service

echo "deploy done"
  SHELL
end
```

## 配置 ssh 互信

以下命令在 k8s-master1 节点执行
```
#在第一个节点生成密钥对
ssh-keygen -q -t rsa  -N "" -f ~/.ssh/id_rsa
#复制公钥
for i in {2..4};do
  ssh-copy-id root@10.0.7.10${i}
done
```
如果你的 ssh 私钥进行了加密，`-N` 选项非空，则可以把私钥的密码加入缓存
```
eval`ssh-agent`
ssh-add
#使用完成后清理
ssh-add -d
ssh-agent -k
#ssh到其他节点时添加 -A 选项
ssh -A 10.0.0.7
```

## 安装二进制 kubernetes 文件


在 k8s-master1 节点安装 kubernets 二进制命令,并发送至其他节点
```
KUBE_VERSION="v1.11.0"
curl  https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz > kubernetes-server-linux-amd64.tar.gz
tar xf kubernetes-server-linux-amd64.tar.gz  --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{let,ctl,adm,-apiserver,-controller-manager,-scheduler,-proxy}

for i in {2..4};do
  scp -rp /usr/local/bin root@10.0.7.10${i}:/usr/local
done
```

创建 kubernets 配置文件存放目录

```
mkdir -p /etc/kubernetes
mkdir -p /etc/kubernetes/{manifests,pki}
```

在所有节点配置命令补全
```
yum -y install bash-completion
echo "source <(kubectl completion bash)" >> /etc/profile.d/kubernetes.sh
source /etc/profile.d/bash_completion.sh
source /etc/profile.d/kubernetes.sh
```
