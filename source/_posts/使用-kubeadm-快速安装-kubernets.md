---
title: 使用 kubeadm 快速安装 kubernets 1.10
date: 2018-06-04 15:53:15
categories:
- kubernetes
---

## 配置 vagrant

Vagrantfile 如下：

```
# -*- mode: ruby -*-
# vi: set ft=ruby :

data_disk = './disk/kubernets_data_disk.vdi'

Vagrant.configure("2") do |config|
  config.vm.box = 'centos/7'
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  config.hostmanager.manage_guest = true
  config.hostmanager.ignore_private_ip = false
  config.hostmanager.include_offline = true
  config.vm.hostname = 'kubernetes'
  config.vm.network "private_network", ip: "10.0.7.101"
  config.vm.provider "virtualbox" do |vb|
    if !File.exist?(data_disk)
      # 100 * 1024M = 100G
      vb.customize ['createhd', '--filename', data_disk, '--size', 100 * 1024]
    end
    vb.customize ['storageattach', :id, '--storagectl', 'IDE', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', data_disk]
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.memory = "4096"
    vb.cpus = "2"
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

## 安装 Docker

安装并配置 docker

```
# 关闭 selinux
sed -ri 's@^(SELINUX=).*@\1disabled@g' /etc/selinux/config
#添加内核参数，确保 iptables 能够对 docker 网桥的流量进行处理。
tee -a /etc/sysctl.d/kubernetes.conf << EOF
#确保 iptables 能够对 docker 网桥的流量进行处理。
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
#解决删除已经死亡的容器时，提示 device or resource busy
fs.may_detach_mounts = 1
EOF
sysctl --system

#安装 docker-ce，安装 conntrack-tools 避免 kube-proxy 的一个报错
curl -sSL https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo >  /etc/yum.repos.d/docker-ce.repo

yum -y install docker-ce conntrack-tools

#启用 overlay2 驱动,和镜像加速
mkdir -p /etc/docker/
cat <<'EOF'> /etc/docker/daemon.json
{
  "registry-mirrors": ["https://fz5yth0r.mirror.aliyuncs.com"],
  "storage-driver": "overlay2",
  "data-root": "/data/docker",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

#启动docker
systemctl start docker && systemctl enable docker
```
## 添加 kuberntees 源

添加国内阿里云源

```
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
setenforce 0
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet
```

修改 docker 的 cgroup-driver

```
sed -ri 's@(--cgroup-driver=).*@\1cgroupfs"@g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl  daemon-reload
systemctl restart kubelet
```

修改基础镜像地址

```
sed  -i '9aEnvironment="KUBELET_EXTRA_ARGS=--pod-infra-container-image=gcr.mirrors.ustc.edu.cn/google_containers/pause-amd64:3.0"' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl  daemon-reload
systemctl restart kubelet
```

手动拉取镜像,具体镜像版本可查看 https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/ 

```
docker pull gcr.mirrors.ustc.edu.cn/google_containers/kube-apiserver-amd64:v1.10.2
docker pull gcr.mirrors.ustc.edu.cn/google_containers/kube-controller-manager-amd64:v1.10.2
docker pull gcr.mirrors.ustc.edu.cn/google_containers/kube-scheduler-amd64:v1.10.2
docker pull gcr.mirrors.ustc.edu.cn/google_containers/kube-proxy-amd64:v1.10.2
docker pull gcr.mirrors.ustc.edu.cn/google_containers/etcd-amd64:3.1.12
docker pull gcr.mirrors.ustc.edu.cn/google_containers/pause-amd64:3.0
docker pull coredns/coredns:1.0.6
```

## Master 节点

临时关闭 swap,永久关闭需修改 `/etc/fstab`

```
swapon -s|awk 'NR>1{print "swapoff",$1}'|bash
```

生成配置文件

```
cat <<EOF > config.yaml
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
 advertiseAddress: 10.0.7.101
networking:
  podSubnet: 10.244.0.0/16
kubernetesVersion: 1.10.2
featureGates:
  CoreDNS: true
imageRepository: "gcr.mirrors.ustc.edu.cn/google_containers"
EOF
```

启动

```
kubeadm init --config config.yaml
```

设置 kubectl 环境变量

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

设置 pod 网络

```
curl -sSL https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml > kube-flannel.yml
sed -i 's@quay.io@quay.mirrors.ustc.edu.cn@g' kube-flannel.yml
kubectl apply -f kube-flannel.yml
```

取消 master 隔离，如果想使用 master 节点运行 pod。

```
kubectl taint nodes --all node-role.kubernetes.io/master-
```

kubectl 命令补全

```
echo "source <(kubectl completion bash)" >> ~/.bashrc
source ~/.bashrc
```

## 其他节点加入
```
kubeadm join 10.0.7.101:6443 --token njcjuu.wxgjh9wf617io2aa --discovery-token-ca-cert-hash sha256:633238412f529267b54a43a7a79e8855fccb2a2d5bfdd1e63029be24ff423c27
```

如果 token 过期，通过下面方法获取

```
#master节点，创建 token
$ kubeadm token create
#master节点，拿到 ca 的 hash 值
$ openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'

# node 节点加入
$ kubeadm join --token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:e18105ef24bacebb23d694dad491e8ef1c2ea9ade944e784b1f03a15a0d5ecea 1.2.3.4:6443
```

## 遇到的问题

coredns 无法解析，导致 heapster 无法正常访问，由于 `Vagrant` 会为所有主机分配IP地址 `10.0.2.15` ，用于获取NAT的外部流量。会导致 flannel 问题，为了防止这种情况，将 `--iface eth1` 标志传递给 flannel ，以便选择第二个接口。

```
sed -i '/kube-subnet-mgr/a\        - --iface=eth1' kube-flannel.yml
```

> 其他问题可查看  https://kubernetes.io/docs/setup/independent/troubleshooting-kubeadm/

