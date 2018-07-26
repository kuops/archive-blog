---
title: 创建 Kubernetes 集群：配置HA
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第五部分`
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

采用 keepalived 和 haproxy 保证 Api-Server 节点的高可用，安装在三台 master 之上

## 配置 Haproxy

haproxy 配置文件如下
```
mkdir -p /etc/haproxy

cat <<EOF> /etc/haproxy/haproxy.cfg
global
  maxconn  2000
  ulimit-n  16384
  log  127.0.0.1 local0 err
  stats timeout 30s

defaults
  log global
  mode  http
  option  httplog
  timeout connect 5000
  timeout client  50000
  timeout server  50000
  timeout http-request 15s
  timeout http-keep-alive 15s

frontend monitor-in
  bind *:33305
  mode http
  option httplog
  monitor-uri /monitor

listen stats
  bind    *:8006
  mode    http
  stats   enable
  stats   hide-version
  stats   uri       /stats
  stats   refresh   30s
  stats   realm     Haproxy\ Statistics
  stats   auth      admin:admin

frontend k8s-api
  bind 0.0.0.0:8443
  bind 127.0.0.1:8443
  mode tcp
  option tcplog
  tcp-request inspect-delay 5s
  default_backend k8s-api

backend k8s-api
  mode tcp
  option tcplog
  option tcp-check
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
  server k8s-api-1 10.0.7.101:6443 check
  server k8s-api-2 10.0.7.102:6443 check
  server k8s-api-3 10.0.7.103:6443 check
EOF
```

## 配置 Keepalived

keepalived.conf 配置文件
```
mkdir -p /etc/keepalived/
cat <<EOF> /etc/keepalived/keepalived.conf
vrrp_script haproxy-check {
    script "/bin/bash /etc/keepalived/check_haproxy.sh"
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance haproxy-vip {
    state BACKUP
    priority 101
    interface eth1
    virtual_router_id 47
    advert_int 3

    unicast_peer {
        10.0.7.101
        10.0.7.102
        10.0.7.103
    }

    virtual_ipaddress {
        10.0.7.100
    }

    track_script {
        haproxy-check
    }
}
EOF
```
keepalived 健康检查脚本
```
cat <<'EOF'> /etc/keepalived/check_haproxy.sh
#!/bin/sh
VIRTUAL_IP=10.0.7.100

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

if ip addr | grep -q $VIRTUAL_IP ; then
    curl -s --max-time 2 --insecure https://${VIRTUAL_IP}:8443/ -o /dev/null || errorExit "Error GET https://${VIRTUAL_IP}:8443/"
fi
EOF
```

## 使用 static-pod 方式运行 keepalived 组件

static-pod 文件配置如下
```
cat <<EOF> /etc/kubernetes/manifests/haproxy-keepalived.yaml
apiVersion: v1
kind: Pod
metadata:
  name: haproxy-keepalived
  namespace: kube-system
  labels: 
    app: "haproxy-keepalived"
    enable: "true"
    service: "base"
spec:
  hostNetwork: true
  securityContext:
    privileged: true
  containers:
  - name: haproxy
    image: haproxy
    command:
    - haproxy
    - -f
    - /etc/haproxy/haproxy.cfg
    volumeMounts:
    - mountPath: /etc/haproxy/haproxy.cfg
      name: haproxy-cfg
      readOnly: true
  - name: keepalived
    image: kuopsme/keepalived:1.4.5
    securityContext:
      privileged: true
    volumeMounts:
    - mountPath: /etc/keepalived/check_haproxy.sh
      name: check-haproxy
      readOnly: true
    - mountPath: /usr/local/etc/keepalived/keepalived.conf
      name: keepalived-cfg
  volumes:
  - hostPath:
      path: /etc/haproxy/haproxy.cfg
    name: haproxy-cfg
  - hostPath:
      path: /etc/keepalived/keepalived.conf
    name: keepalived-cfg
  - hostPath:
      path: /etc/keepalived/check_haproxy.sh
    name: check-haproxy
EOF
```

## 验证配置是否正常

正常结果应该如下，此时可以 ping 通 vip，由于没有配置 master 节点，keepalived 中优先级一直在调整，ip 在三个节点间不停漂移。
```
[root@k8s-master1 ~]# docker ps --filter name=k8s_keepalived --filter name=k8s_haproxy
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS               NAMES
5b85bee08ee1        1e6a7a31599b        "/container/tool/run"    4 minutes ago       Up 4 minutes                            k8s_keepalived_haproxy-keepalived-k8s-master1_kube-system_cb54482674a4d86f6a29ee50ee40a37a_0
4ad2593c751c        haproxy             "haproxy -f /etc/hap…"   4 minutes ago       Up 4 minutes                            k8s_haproxy_haproxy-keepalived-k8s-master1_kube-system_cb54482674a4d86f6a29ee50ee40a37a_0
```
