---
title: 创建 Kubernetes 集群：配置 Master 组件
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第六部分`
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

## 使用二进制方式部署

### 配置 Kube-apiserver

替换 `NODE_IP` 为当前  master 节点 IP ，并启动 Kube-apiserver

```
NODE_IP="10.0.7.101"

cat <<EOF> /usr/lib/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --authorization-mode=Node,RBAC \\
  --enable-admission-plugins=Initializers,DefaultStorageClass,DefaultTolerationSeconds,LimitRanger,NamespaceLifecycle,NodeRestriction,PersistentVolumeClaimResize,ResourceQuota,ServiceAccount \\
  --advertise-address=${NODE_IP} \\
  --bind-address=0.0.0.0 \\
  --insecure-port=0 \\
  --secure-port=6443 \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --enable-swagger-ui=true \\
  --storage-backend=etcd3 \\
  --etcd-cafile=/etc/kubernetes/pki/ca.crt \\
  --etcd-certfile=/etc/kubernetes/pki/etcd-client.crt \\
  --etcd-keyfile=/etc/kubernetes/pki/etcd-client.key \\
  --etcd-servers=https://10.0.7.101:2379,https://10.0.7.102:2379,https://10.0.7.103:2379 \\
  --event-ttl=1h \\
  --enable-bootstrap-token-auth \\
  --client-ca-file=/etc/kubernetes/pki/ca.crt \\
  --kubelet-https \\
  --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key \\
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
  --runtime-config=api/all \\
  --service-cluster-ip-range=10.96.0.0/16 \\
  --service-node-port-range=30000-32767 \\
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \\
  --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.crt \\
  --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver.key \\
  --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \\
  --requestheader-username-headers=X-Remote-User \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-allowed-names=front-proxy-client \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt \\
  --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key \\
  --feature-gates=PodShareProcessNamespace=true \\
  --v=2

Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl restart kube-apiserver
systemctl status kube-apiserver -l
```

### Kube-apiserver 部分启动参数说明

- `--authorization-mode`: 在安全端口上执行授权的插件列表。以逗号分隔的列表：`AlwaysAllow`，`AlwaysDeny`，`ABAC`，`Webhook`，`RBAC`，`Node`。

- `--enable-admission`: 除了默认启用的插件之外，应该启用的插件插件。逗号分隔录取插件列表,关于列表推荐，可以根据版本，选择[官方推荐列表](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)。

- `--advertise-address`: 用于向群集成员通告 apiserver 的 IP 地址。该地址必须可由群集的其余部分访问。如果为空，则使用 `--bind-address`。如果未指定 `--bind-address`，将使用主机的默认接口。

- `--insecure-port`: 非安全端口 (http),为 0 表示不启用非安全端口。

- `--secure-port`: 安全端口 (https)。

- `--allow-privileged`: 如果为 true，则允许特权容器。

- `--apiserver-count`: 群集中运行的 api-server 数量。

- `--audit-log-path`: 审计日志存放的地方。

- `--enable-swagger-ui`: 访问 swagger, url /swagger-ui/

- `--event-ttl`: 保留事件的时间

- `--enable-bootstrap-token-auth`: 允许在 `kube-system` 命名空间中允许 `bootstrap.kubernetes.io/token` 类型的 secret 用于TLS引导认证。

- `--client-ca-file`: 启用客户端证书认证，通过 CA证书与客户端证书的 CommonName（CN） 对应的标识进行身份验证。

- `--kubelet-https`: 使用 https 与 kubelet 进行通信。

- `--kubelet-preferred-address-types`: 用于 kubelet 连接的首选节点地址类型的列表。

- `--runtime-config=api/all`: 一组 key/value ，描述可以传递给 apiserver 的运行时配置。`<group>/<version>`密钥可用于打开/关闭特定的 api 版本。api/all 是控制所有 api 版本的特殊键。

- `--service-cluster-ip-range`: service 资源对象的 ip 的 CIDR。

- `--service-node-port-range`: NodePort 使用的端口范围。

- `--service-account-key-file`: 用于验证 ServiceAccount 令牌。如果未指定，则使用 `--tls-private-key-file`。必须在提供 `--service-account-signing-key` 时指定。

- `--feature-gates=PodShareProcessNamespace`: 配置 Pod 间进程共享




### 配置 kube-controller-manager

```
cat<<EOF> /usr/lib/systemd/system/kube-controller-manager.service 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --allocate-node-cidrs=true \\
  --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig \\
  --address=127.0.0.1 \\
  --leader-elect=true \\
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \\
  --cluster-name=kubernetes \\
  --cluster-cidr=10.244.0.0/16 \\
  --service-cluster-ip-range=10.96.0.0/16 \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca.key \\
  --root-ca-file=/etc/kubernetes/pki/ca.crt \\
  --use-service-account-credentials=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --experimental-cluster-signing-duration=86700h \\
  --feature-gates=RotateKubeletClientCertificate=true \\
  --v=2
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl restart kube-controller-manager
systemctl status kube-controller-manager -l
```

### Kube-apiserver 部分启动参数说明

- `--allocate-node-cidrs`:leader-elect 是否为 Pod 分配 CIDR。

- `--leader-elect`: 用于选举领导者，在高可用时保证集群中只有一位领导者

- `service-account-private-key-file`: 用于生成 service account tokens.

- `--cluster-cidr`: 集群中 Pod 的 CIDR 范围

- `--controllers`： 要启用的控制器列表，默认为 bootstrapsigner，tokencleaner

- `--experimental-cluster-signing-duration`: 自动生成的证书有效期，默认 8670h

- `--feature-gates=RotateKubeletServerCertificate=true`：kublet 证书的自动更新


### 配置 kube-scheduler

```
cat > /usr/lib/systemd/system/kube-scheduler.service << EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --kubeconfig=/etc/kubernetes/scheduler.kubeconfig \\
  --address=127.0.0.1 \\
  --v=2
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-scheduler
systemctl restart kube-scheduler
systemctl status kube-scheduler -l
```


## 通过 static_pod 方式部署

### 部署 kube-apiserver

替换 `NODE_IP` 为自己的 IP

```
NODE_IP="10.0.7.101"

cat <<EOF> /etc/kubernetes/manifests/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver 
    - --authorization-mode=Node,RBAC 
    - --enable-admission-plugins=Initializers,DefaultStorageClass,DefaultTolerationSeconds,LimitRanger,NamespaceLifecycle,NodeRestriction,PersistentVolumeClaimResize,ResourceQuota,ServiceAccount 
    - --advertise-address=${NODE_IP} 
    - --bind-address=0.0.0.0 
    - --insecure-port=0 
    - --secure-port=6443 
    - --allow-privileged=true 
    - --apiserver-count=3 
    - --audit-log-maxage=30 
    - --audit-log-maxbackup=3 
    - --audit-log-maxsize=100 
    - --audit-log-path=/var/log/audit.log 
    - --enable-swagger-ui=true 
    - --storage-backend=etcd3 
    - --etcd-cafile=/etc/kubernetes/pki/ca.crt 
    - --etcd-certfile=/etc/kubernetes/pki/etcd-client.crt 
    - --etcd-keyfile=/etc/kubernetes/pki/etcd-client.key 
    - --etcd-servers=https://10.0.7.101:2379,https://10.0.7.102:2379,https://10.0.7.103:2379 
    - --event-ttl=1h 
    - --enable-bootstrap-token-auth 
    - --client-ca-file=/etc/kubernetes/pki/ca.crt 
    - --kubelet-https 
    - --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt 
    - --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key 
    - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname 
    - --runtime-config=api/all 
    - --service-cluster-ip-range=10.96.0.0/16 
    - --service-node-port-range=30000-32767 
    - --service-account-key-file=/etc/kubernetes/pki/sa.pub 
    - --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.crt 
    - --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver.key 
    - --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
    - --requestheader-username-headers=X-Remote-User
    - --requestheader-group-headers=X-Remote-Group
    - --requestheader-allowed-names=front-proxy-client
    - --requestheader-extra-headers-prefix=X-Remote-Extra-
    - --feature-gates=PodShareProcessNamespace=true
    - --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt
    - --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key
    - --v=2
    image: kuops/kube-apiserver-amd64:v1.11.0
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: ${NODE_IP}
        path: /healthz
        port: 6443
        scheme: HTTPS
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: kube-apiserver
    resources:
      requests:
        cpu: 250m
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /etc/ssl/certs
      name: ca-certs
      readOnly: true
    - mountPath: /etc/pki
      name: etc-pki
      readOnly: true
  hostNetwork: true
  priorityClassName: system-cluster-critical
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /etc/ssl/certs
      type: DirectoryOrCreate
    name: ca-certs
  - hostPath:
      path: /etc/pki
      type: DirectoryOrCreate
    name: etc-pki
EOF
```

### 部署 kube-controller-manager

```
cat <<EOF> /etc/kubernetes/manifests/kube-controller-manager.yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-controller-manager
    - --allocate-node-cidrs=true
    - --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig
    - --address=127.0.0.1
    - --leader-elect=true
    - --service-account-private-key-file=/etc/kubernetes/pki/sa.key
    - --cluster-name=kubernetes
    - --cluster-cidr=10.244.0.0/16
    - --service-cluster-ip-range=10.96.0.0/16
    - --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
    - --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
    - --root-ca-file=/etc/kubernetes/pki/ca.crt
    - --use-service-account-credentials=true
    - --controllers=*,bootstrapsigner,tokencleaner
    - --experimental-cluster-signing-duration=86700h
    - --feature-gates=RotateKubeletClientCertificate=true
    - --v=2
    image: kuops/kube-controller-manager-amd64:v1.11.0
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10252
        scheme: HTTP
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: kube-controller-manager
    resources:
      requests:
        cpu: 200m
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /etc/ssl/certs
      name: ca-certs
      readOnly: true
    - mountPath: /etc/kubernetes/controller-manager.kubeconfig
      name: kubeconfig
      readOnly: true
    - mountPath: /usr/libexec/kubernetes/kubelet-plugins/volume/exec
      name: flexvolume-dir
    - mountPath: /etc/pki
      name: etc-pki
      readOnly: true
  hostNetwork: true
  priorityClassName: system-cluster-critical
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /etc/ssl/certs
      type: DirectoryOrCreate
    name: ca-certs
  - hostPath:
      path: /etc/kubernetes/controller-manager.kubeconfig
      type: FileOrCreate
    name: kubeconfig
  - hostPath:
      path: /usr/libexec/kubernetes/kubelet-plugins/volume/exec
      type: DirectoryOrCreate
    name: flexvolume-dir
  - hostPath:
      path: /etc/pki
      type: DirectoryOrCreate
    name: etc-pki
EOF
```

### 部署 kube-scheduler

```
cat <<EOF> /etc/kubernetes/manifests/kube-scheduler.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-scheduler
    - --address=127.0.0.1
    - --kubeconfig=/etc/kubernetes/scheduler.kubeconfig
    - --leader-elect=true
    - --v=2
    image: kuops/kube-scheduler-amd64:v1.11.0
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10251
        scheme: HTTP
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: kube-scheduler
    resources:
      requests:
        cpu: 100m
    volumeMounts:
    - mountPath: /etc/kubernetes/scheduler.kubeconfig
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  priorityClassName: system-cluster-critical
  volumes:
  - hostPath:
      path: /etc/kubernetes/scheduler.kubeconfig
      type: FileOrCreate
    name: kubeconfig
EOF
```

## 验证

通过 kubectl 查看组件的健康状态

```
[root@k8s-master1 pki]# kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok                   
scheduler            Healthy   ok                   
etcd-1               Healthy   {"health": "true"}   
etcd-0               Healthy   {"health": "true"}   
etcd-2               Healthy   {"health": "true"}   
```
