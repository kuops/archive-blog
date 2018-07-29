---
title: 创建 Kubernetes 集群：配置 kubelet 组件
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第八部分`
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

## 配置 bootrstrap 配置文件

在所有节点安装 kubelet 配置文件

在 worker 节点，通过 `kube-public` 命名空间获取 kubernets 的 ca.crt 和 bootstrap.kubeconfig 文件

```
mkdir -p /etc/kubernetes/pki

kubectl -n kube-public get cm/cluster-info \
        --server https://10.0.7.100:8443 --insecure-skip-tls-verify=true \
        --output=jsonpath='{.data.ca\.crt}' \
  | tee /etc/kubernetes/pki/ca.crt

kubectl -n kube-public get cm/cluster-info \
        --server https://10.0.7.100:8443 --insecure-skip-tls-verify=true \
        --output=jsonpath='{.data.bootstrap\.kubeconfig}' \
  | tee /etc/kubernetes/bootstrap.kubeconfig
```

为 kubelet 设置认证参数，将先前的 `BOOTSTRAP_TOKEN` 加入 bootstrap.kubeconfig 的客户端认证
```
#获取 token-id
kubectl -n kube-system get secrets bootstrap-token-341128 -o jsonpath={.data.token-id}|base64 -d

#获取 token-secret
kubectl -n kube-system get secrets bootstrap-token-341128 -o jsonpath={.data.token-secret}|base64 -d

#token 等于  token-id.token-secret
BOOTSTRAP_TOKEN="341128.628bcf8b9bb7b7b0"

kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=/etc/kubernetes/bootstrap.kubeconfig
```

## 部署 kubelet 组件

kubelet 配置文件

```
CLUSTER_DNS_IP=10.96.0.10

cat <<EOF> /etc/kubernetes/kubelet-conf.yaml
address: 0.0.0.0
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: cgroupfs
cgroupsPerQOS: true
clusterDNS:
- ${CLUSTER_DNS_IP}
clusterDomain: cluster.local
containerLogMaxFiles: 5
containerLogMaxSize: 10Mi
contentType: application/vnd.kubernetes.protobuf
cpuCFSQuota: true
cpuManagerPolicy: none
cpuManagerReconcilePeriod: 10s
enableControllerAttachDetach: true
enableDebuggingHandlers: true
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 20s
hairpinMode: promiscuous-bridge
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 20s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
iptablesDropBit: 15
iptablesMasqueradeBit: 14
kubeAPIBurst: 10
kubeAPIQPS: 5
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
port: 10250
readOnlyPort: 10255
registryBurst: 10
registryPullQPS: 5
resolvConf: /etc/resolv.conf
rotateCertificates: true
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
volumeStatsAggPeriod: 1m0s
EOF
```

`rotateCertificates: true`: 启用证书轮转


kubelet 的 systemd 启动文件

```
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.conf \\
  --config=/etc/kubernetes/kubelet-conf.yaml \\
  --pod-infra-container-image=kuops/pause-amd64:3.1 \\
  --allow-privileged=true \\
  --network-plugin=cni \\
  --cni-conf-dir=/etc/cni/net.d \\
  --cni-bin-dir=/opt/cni/bin \\
  --cert-dir=/etc/kubernetes/pki
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kubelet
systemctl restart kubelet
systemctl status kubelet -l
```

## 节点标签

禁止 master 节点接受调度请求，并添加节点标签
```

for i in {1..3}; do
  kubectl label node k8s-master${i} node-role.kubernetes.io/master=
  kubectl taint nodes k8s-master${i}  node-role.kubernetes.io/master=:NoSchedule
done

kubectl label node k8s-node1 node-role.kubernetes.io/node=
```

## 验证 kubelet

```
[root@k8s-master1 ~]# kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
node-csr-VHBDGef-_2xDG2_xVCTzCx6Yf2Q1gsd4gP06_GITr-Q   13m       system:bootstrap:38d0c5   Approved,Issued
node-csr-WJTwo06iyGC7qScxvGTepiGRMxlJG5Ivr8YrsSb4UAc   9m        system:bootstrap:38d0c5   Approved,Issued
node-csr-a-m4ZHjMECh5oAu1bl6IfzkdOzwOxW0g0LRCPTR1h3I   13m       system:bootstrap:38d0c5   Approved,Issued
node-csr-thC3ha4JvaW3HwQtwLptYq7uLEhkIWZ4_4v1x3y3Las   16m       system:bootstrap:38d0c5   Approved,Issued

[root@k8s-master1 ~]# kubectl get node
NAME          STATUS     ROLES     AGE       VERSION
k8s-master1   NotReady   <none>    10m       v1.11.0
k8s-master2   NotReady   <none>    7m        v1.11.0
k8s-master3   NotReady   <none>    7m        v1.11.0
k8s-node1     NotReady   <none>    3m        v1.11.0

[root@k8s-master1 ~]# kubectl get pod --all-namespaces 
NAMESPACE     NAME                                  READY     STATUS    RESTARTS   AGE
kube-system   etcd-k8s-master1                      1/1       Running   8          8m
kube-system   etcd-k8s-master2                      1/1       Running   1          5m
kube-system   etcd-k8s-master3                      1/1       Running   1          5m
kube-system   haproxy-keepalived-k8s-master1        2/2       Running   0          8m
kube-system   haproxy-keepalived-k8s-master2        2/2       Running   0          5m
kube-system   haproxy-keepalived-k8s-master3        2/2       Running   0          5m
kube-system   kube-apiserver-k8s-master1            1/1       Running   0          8m
kube-system   kube-apiserver-k8s-master3            1/1       Running   0          5m
kube-system   kube-controller-manager-k8s-master1   1/1       Running   0          8m
kube-system   kube-controller-manager-k8s-master2   1/1       Running   0          5m
kube-system   kube-controller-manager-k8s-master3   1/1       Running   0          5m
kube-system   kube-scheduler-k8s-master1            1/1       Running   0          8m
kube-system   kube-scheduler-k8s-master2            1/1       Running   0          5m
kube-system   kube-scheduler-k8s-master3            1/1       Running   0          5m
```
