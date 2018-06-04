---
title: 使用-kubeadm-快速安装-kubernets.md
date: 2018-06-04 15:53:15
categories:
- kubernetes
---


## 升级 4.4 内核

升级系统内核，并设置默认使用 4.4 内核启动
```
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum --enablerepo=elrepo-kernel install -y kernel-lt
sed  -i 's@GRUB_DEFAULT=.*@GRUB_DEFAULT=0@' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot
```

## 安装 Docker

安装并配置 docker
```
#添加内核参数，确保 iptables 能够对 docker 网桥的流量进行处理。
tee -a /etc/sysctl.d/kubernetes.conf << EOF
#确保 iptables 能够对 docker 网桥的流量进行处理。
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

#安装 docker-ce，安装 conntrack-tools 避免 kube-proxy 的一个报错
wget -O /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum -y install docker-ce conntrack-tools

#启用 overlay2 驱动,和镜像加速
mkdir -p /etc/docker/
cat <<'EOF'> /etc/docker/daemon.json
{
  "registry-mirrors": ["https://fz5yth0r.mirror.aliyuncs.com"],
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
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
手动拉取镜像,具体镜像版本可查看`https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/`
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
 advertiseAddress: 10.0.7.102
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
wget https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
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
kubeadm join 10.0.7.102:6443 --token 16ha17.48btyw5cpxee5chb --discovery-token-ca-cert-hash sha256:fb42cb7b320b154bd572c915821ce07416b23b09fb815765d8b098f29b1ec694
```



