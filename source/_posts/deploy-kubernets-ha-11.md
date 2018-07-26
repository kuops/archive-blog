---
title: 创建 Kubernetes 集群：配置 ipvs
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第十一部分`
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

在 CentOS 7 中 ，由于 `ipset` 命令有 bug, 主要是不支持 `comment` 命令, 这个会在 `kernel-3.10.0-894.el7` 中修复，但目前还没有此内核的包 https://bugzilla.redhat.com/show_bug.cgi?id=1557599#c6

```
[root@k8s-master1 ~]# ipset create foo hash:ip comment
ipset v6.29: Unknown argument: `comment'
Try `ipset help' for more information.
```

## 升级内核

通过升级内核来解决此问题

```
yum -y install http://mirrors.ustc.edu.cn/elrepo/kernel/el7/x86_64/RPMS/kernel-lt-4.4.143-1.el7.elrepo.x86_64.rpm
sed  -i 's@GRUB_DEFAULT=.*@GRUB_DEFAULT=0@' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot
```

查看是否正常

```
[root@k8s-node1 ~]# ipset  list
Name: foo
Type: hash:ip
Revision: 4
Header: family inet hashsize 1024 maxelem 65536 comment
Size in memory: 128
References: 0
Members:
[root@k8s-node1 ~]# ipset  destroy foo
```

## 设置 kube-proxy

启用 ipvs ，如果使用二进制 kube-proxy

```
mkdir /var/lib/kube-proxy

cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --proxy-mode=ipvs \\
  --ipvs-scheduler=rr
  --v=2
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-proxy
systemctl restart kube-proxy
systemctl status kube-proxy -l
```

如果使用 daemonset , 则修改 configmap 的如下字段

```
......
    ipvs:
      minSyncPeriod: 0s
      scheduler: "rr"
      syncPeriod: 30s
......
    mode: "ipvs"

#修改完成之后重新应用 configmap 
kubectl apply -f kube-proxy-configmap.yaml
```
## 验证

修改完成之后,重启 pod 验证

```
[root@k8s-master1 ~]# docker restart k8s_kube-proxy_kube-proxy-v72rj_kube-system_2075a5b8-9081-11e8-9891-525400c9c704_2
[root@k8s-master1 ~]# ipvsadm -ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.96.0.1:443 rr
  -> 10.0.7.101:6443              Masq    1      1          0         
  -> 10.0.7.102:6443              Masq    1      0          0         
  -> 10.0.7.103:6443              Masq    1      0          0         
TCP  10.96.0.10:53 rr
  -> 10.244.1.6:53                Masq    1      0          0         
  -> 10.244.1.7:53                Masq    1      0          0         
UDP  10.96.0.10:53 rr
  -> 10.244.1.6:53                Masq    1      0          0         
  -> 10.244.1.7:53                Masq    1      0          0  
```
