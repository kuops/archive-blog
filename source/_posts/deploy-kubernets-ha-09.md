---
title: 创建 Kubernetes 集群：配置 kube-proxy 组件
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第九部分`
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

## 配置 kube-proxy

> 如果您使用之前创建的 x509 证书来验证 kube-proxy 角色时，不虚要创建 kube-proxy 服务帐户。

创建服务帐户后，将自动创建JWT令牌。

创建一个 kube-proxy 的 `service account` ：

```
kubectl -n kube-system create serviceaccount kube-proxy
```

将 kube-proxy 的  `serviceaccount` 绑定到 clusterrole `system:node-proxier` 以允许 RBAC：

```
kubectl create clusterrolebinding kubeadm:node-proxier \
        --clusterrole system:node-proxier \
        --serviceaccount kube-system:kube-proxy
```

### 使用二进制方式部署 kube-proxy

创建一个 kube-proxy kubeconfig：
```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_CONFIG="kube-proxy.kubeconfig"

SECRET=$(kubectl -n kube-system get sa/kube-proxy \
                 --output=jsonpath='{.secrets[0].name}')

JWT_TOKEN=$(kubectl -n kube-system get secret/$SECRET \
                    --output=jsonpath='{.data.token}' | base64 -d)

kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

kubectl config set-context ${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${CLUSTER_NAME} \
  --namespace=default \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

kubectl config set-credentials ${CLUSTER_NAME} \
  --token=${JWT_TOKEN} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

kubectl config use-context ${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
```


分发 kubconfig 文件到其他节点

```
for i in {2..4}; do
  scp -p -- /etc/kubernetes/kube-proxy.kubeconfig 10.0.7.10$i:/etc/kubernetes/
done
```

kube-proxy 的 systemd 配置文件如下
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
  --proxy-mode=iptables \\
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

### 使用 daemonset 方式部署 kube-proxy


kube-proxy 的 configmap 文件

```

KUBE_APISERVER="https://10.0.7.100:8443"

cat <<EOF> kube-proxy-configmap.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-proxy
  namespace: kube-system
  labels:
    app: kube-proxy
data:
  kubeconfig.conf: |-
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        server: ${KUBE_APISERVER}
      name: kubernetes
    contexts:
    - context:
        cluster: kubernetes
        namespace: default
        user: kubernetes
      name: kubernetes
    current-context: kubernetes
    users:
    - name: kubernetes
      user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
  config.conf: |-
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    bindAddress: 0.0.0.0
    clientConnection:
      acceptContentTypes: ""
      burst: 10
      contentType: application/vnd.kubernetes.protobuf
      kubeconfig: /var/lib/kube-proxy/kubeconfig.conf
      qps: 5
    clusterCIDR: 10.244.0.0/16
    configSyncPeriod: 15m0s
    conntrack:
      max: null
      maxPerCore: 32768
      min: 131072
      tcpCloseWaitTimeout: 1h0m0s
      tcpEstablishedTimeout: 24h0m0s
    enableProfiling: false
    healthzBindAddress: 0.0.0.0:10256
    hostnameOverride: ""
    iptables:
      masqueradeAll: false
      masqueradeBit: 14
      minSyncPeriod: 0s
      syncPeriod: 30s
    ipvs:
      minSyncPeriod: 0s
      scheduler: ""
      syncPeriod: 30s
    kind: KubeProxyConfiguration
    metricsBindAddress: 127.0.0.1:10249
    mode: ""
    nodePortAddresses: null
    oomScoreAdj: -999
    portRange: ""
    resourceContainer: /kube-proxy
    udpIdleTimeout: 250ms
EOF

kubectl create -f kube-proxy-configmap.yaml
```

kube-proxy pod  通过 `Service Account` 获取到 ca.crt 和 token，通过 `Admission Controller` 实现的。当此插件处于活动状态时（默认情况下在大多数发行版中），则在创建或修改pod时执行以下操作：

- 如果 pod 没有 ServiceAccount 设置，则将其设置 ServiceAccount 为 `default`。

- 如果 pod 不包含任何内容 `ImagePullSecrets`，则将 ServiceAccount 中的 `ImagePullSecrets` 添加到 pod 中。

- 将 访问 api 的 token 作为 `volume` 挂载到 pod 中，挂载在 `/var/run/secrets/kubernetes.io/serviceaccount`

kube-proxy 的 daemonset 的配置文件

```
cat <<EOF> kube-proxy-ds.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
    spec:
      priorityClassName: system-node-critical
      containers:
      - name: kube-proxy
        image: kuops/kube-proxy-amd64:v1.11.0
        imagePullPolicy: IfNotPresent
        command:
        - /usr/local/bin/kube-proxy
        - --config=/var/lib/kube-proxy/config.conf
        - --proxy-mode=iptables
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
        - mountPath: /run/xtables.lock
          name: xtables-lock
          readOnly: false
        - mountPath: /lib/modules
          name: lib-modules
          readOnly: true
      hostNetwork: true
      serviceAccountName: kube-proxy
      volumes:
      - name: kube-proxy
        configMap:
          name: kube-proxy
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - operator: Exists
EOF

kubectl create -f kube-proxy-ds.yaml
```
验证
```
[root@k8s-master1 ~]# kubectl  get pod -n kube-system  -l k8s-app=kube-proxy
NAME               READY     STATUS    RESTARTS   AGE
kube-proxy-4242d   1/1       Running   0          17m
kube-proxy-994h9   1/1       Running   0          17m
kube-proxy-dwmc5   1/1       Running   0          17m
kube-proxy-gww9b   1/1       Running   0          17m
```
