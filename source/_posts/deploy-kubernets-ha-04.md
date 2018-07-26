---
title: 创建 Kubernetes 集群：配置etcd
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第四部分`
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

## ETCD

Etcd是一个分布式，一致的 K/V 存储，用于配置管理，服务发现和协调分布式工作。

Kubernete 使用 etcd  来存储 Kubernetes 集群的配置数据，比如集群的状态（集群中存在哪些节点，应该运行哪些pod，运行哪些节点等）。

## 使用 static-pod 方式部署 etcd 集群

要使用 static-pod 的前提需要在 master 节点启动 kubelet 进程，这里只是临时使用一下，具体 kubelet 的详细配置在 kubelet 一文。

```
cat << EOF > /usr/lib/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kubelet \\
     --cgroup-driver=cgroupfs \\
     --pod-infra-container-image=kuops/pause-amd64:3.1 \\
     --pod-manifest-path=/etc/kubernetes/manifests \\
     --allow-privileged=true
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet
systemctl enable kubelet
```

在 所有 master 节点部署 etcd 的 static-pod，其他节点修改对应 `ETCD_NAME` 为 `etcd1` 和 `etcd2`，ip 改为节点 IP。

```
ETCD_NAME=etcd0
ETCD_IP="10.0.7.101"
ETCD_IPS=(10.0.7.101 10.0.7.102 10.0.7.103)
cat > /etc/kubernetes/manifests/etcd.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --name=${ETCD_NAME}
    - --data-dir=/var/lib/etcd
    - --listen-client-urls=https://127.0.0.1:2379,https://${ETCD_IP}:2379
    - --advertise-client-urls=https://${ETCD_IP}:2379
    - --listen-peer-urls=https://${ETCD_IP}:2380
    - --initial-advertise-peer-urls=https://${ETCD_IP}:2380
    - --cert-file=/certs/etcd-server.crt
    - --key-file=/certs/etcd-server.key
    - --client-cert-auth
    - --trusted-ca-file=/certs/ca.crt
    - --peer-cert-file=/certs/etcd-peer.crt
    - --peer-key-file=/certs/etcd-peer.key
    - --peer-client-cert-auth
    - --peer-trusted-ca-file=/certs/ca.crt
    - --initial-cluster=etcd0=https://${ETCD_IPS[0]}:2380,etcd1=https://${ETCD_IPS[1]}:2380,etcd2=https://${ETCD_IPS[2]}:2380
    - --initial-cluster-token=my-etcd-token
    - --initial-cluster-state=new
    image: kuops/etcd-amd64:3.2.18
    name: etcd
    livenessProbe:
      exec:
        command:
        - /bin/sh
        - -ec
        - ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/certs/ca.crt
          --cert=/certs/etcd-client.crt --key=/certs/etcd-client.key
          get foo
      failureThreshold: 8
      initialDelaySeconds: 15
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /certs
      name: etcd-certs
    env:
    - name: PUBLIC_IP
      valueFrom:
        fieldRef:
          fieldPath: status.hostIP
    - name: PRIVATE_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: PEER_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki
    name: etcd-certs
EOF
```
测试 etcd 节点的健康状态
```
docker run --rm -it --net host \
    -v /etc/kubernetes/pki:/certs \
    kuops/etcd-amd64:3.2.18 etcdctl \
    --cert-file /certs/etcd-client.crt \
    --key-file /certs/etcd-client.key  \
    --ca-file /certs/ca.crt \
    --endpoints https://${ETCD_IP}:2379 cluster-health
```
如返回以下状态，则表示成功
```
member 95eeae6abe63f1f7 is healthy: got healthy result from https://10.0.7.101:2379
member 97163ac967ae92a3 is healthy: got healthy result from https://10.0.7.103:2379
member b84b1769937d3db7 is healthy: got healthy result from https://10.0.7.102:2379
cluster is healthy
```

## 使用二进制方式部署 etcd 集群

安装 etcd 并创建存储目录
```
mkdir -p /var/lib/etcd
ETCD_VER=v3.2.18
wget https://storage.googleapis.com/etcd/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xf etcd-${ETCD_VER}-linux-amd64.tar.gz  --strip-components=1 -C /usr/local/bin etcd-${ETCD_VER}-linux-amd64/{etcd,etcdctl}
scp /usr/local/bin/etcd* root@10.0.7.102:/usr/local/bin/
scp /usr/local/bin/etcd* root@10.0.7.103:/usr/local/bin/
```
设置 unit file 并启动 etcd,其他节点修改对应 `ETCD_NAME` 为 `etcd1` 和 `etcd2`，ip 改为节点 IP。
```
ETCD_NAME=etcd0
ETCD_IP="10.0.7.101"
ETCD_IPS=(10.0.7.101 10.0.7.102 10.0.7.103)

cat<<EOF> /usr/lib/systemd/system/etcd.service 
[Unit]
Description=etcd
Documentation=https://coreos.com/etcd/docs/latest/
After=network.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd
ExecStart=/usr/local/bin/etcd \\
    --name=${ETCD_NAME} \\
    --data-dir=/var/lib/etcd \\
    --listen-client-urls=https://127.0.0.1:2379,https://${ETCD_IP}:2379 \\
    --advertise-client-urls=https://${ETCD_IP}:2379 \\
    --listen-peer-urls=https://${ETCD_IP}:2380 \\
    --initial-advertise-peer-urls=https://${ETCD_IP}:2380 \\
    --cert-file=/etc/kubernetes/pki/etcd-server.crt \\
    --key-file=/etc/kubernetes/pki/etcd-server.key \\
    --client-cert-auth \\
    --trusted-ca-file=/etc/kubernetes/pki/ca.crt \\
    --peer-cert-file=/etc/kubernetes/pki/etcd-peer.crt \\
    --peer-key-file=/etc/kubernetes/pki/etcd-peer.key \\
    --peer-client-cert-auth \\
    --peer-trusted-ca-file=/etc/kubernetes/pki/ca.crt \\
    --initial-cluster=etcd0=https://${ETCD_IPS[0]}:2380,etcd1=https://${ETCD_IPS[1]}:2380,etcd2=https://${ETCD_IPS[2]}:2380 \\
    --initial-cluster-token=my-etcd-token \\
    --initial-cluster-state=new \\
    --heartbeat-interval 1000 \\
    --election-timeout 5000

Restart=always
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart etcd
systemctl enable etcd
```
验证 ETCD 集群状态
```
 etcdctl \
    --cert-file /etc/kubernetes/pki/etcd-client.crt \
    --key-file /etc/kubernetes/pki/etcd-client.key  \
    --ca-file /etc/kubernetes/pki/ca.crt \
    --endpoints https://${ETCD_IP}:2379 cluster-health
```

## ETCD 部分启动参数说明

|参数|说明|
|---|---|
|--name|当前集群成员的名称，全局唯一|
|--data-dir|ETCD数据存放的位置|
|--listen-client|客户端访问的入口|
|--advertise-client-urls|etcd 向外部通告的自己的 url，客户端通过解析这些 url，并连接到集群|
|--listen-peer-urls|邻居节点通信访问的入口|
|--initial-advertise-peer-urls|邻居节点通过解析这些 url，并连接到集群|
|--initial-cluster-state|新建集群的时候，这个值为 new，已经存在的集群，这个值为 existing|
|--initial-cluster-token|创建集群的 token，这个值每个集群保持唯一。这样的话，如果你要重新创建集群，即使配置和之前一样，也会再次生成新的集群和节点 uuid|
|--heartbeat-interval|发送心跳间隔，单位毫秒|
|--election-timeout|选举超时时间，单位毫秒|
