---
title: 创建 Kubernetes 集群：配置 Ceph 存储
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第十六部分`
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

## 创建 ceph 集群

由于 kube-controller-manager 中没有包含 rdb 命令，这里使用 rdb-provisioner 进行 ceph 和 kubernetes 集群的连接


### 安装 ceph-deploy

在 `k8s-master1` 安装 `ceph-deploy`， `ceph-deploy` 是一个快速部署 ceph 集群的工具，这里将 ceph 部署到其他三台节点之上

```
cat <<EOF> /etc/yum.repos.d/ceph.repo
[ceph-noarch]
name=Ceph noarch packages
baseurl=http://mirrors.ustc.edu.cn/ceph/rpm-luminous/el7/noarch/
enabled=1
gpgcheck=1
type=rpm-md
gpgkey=https://download.ceph.com/keys/release.asc
EOF
yum -y install ceph-deploy python-pip
```

### 配置 ceph 集群

ceph 节点，使用 `k8s-master2` `k8s-master3` `k8s-node1` 三个节点作为 ceph 节点

使用 ceph-deploy 部署 ceph

```
mkdir my-cluster
cd my-cluster
ceph-deploy --username root new k8s-master2 k8s-master3 k8s-node1

cat <<EOF> ceph.conf
[global]
fsid = cef110e3-b05e-41c8-8a1e-f92f60baa27c
mon_initial_members = k8s-master2, k8s-master3, k8s-node1
mon_host = 10.0.7.102,10.0.7.103,10.0.7.104
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx
public_network=10.0.7.0/24
EOF

ceph-deploy --username=root install --release=luminous --repo-url=http://mirrors.ustc.edu.cn/ceph/rpm-luminous/el7 k8s-master2 k8s-master3 k8s-node1
```
配置监控、并收集所有密钥：

```
ceph-deploy --username=root  mon create-initial
```
发送 ceph-deploy 配置文件和密钥至其他节点

```
ceph-deploy --username=root admin k8s-master2 k8s-master3 k8s-node1
```
部署一个后台管理程序

```
ceph-deploy mgr create k8s-master2 k8s-master3 k8s-node1
```

创建 osd

```
ceph-deploy --username=root osd create --data /dev/sdb k8s-master2
ceph-deploy --username=root osd create --data /dev/sdb k8s-master3
ceph-deploy --username=root osd create --data /dev/sdb k8s-node1
```
查看集群运行情况

```
ssh k8s-master2 ceph health
```

要使用CephFS，您至少需要一个元数据服务器。执行以下操作以创建元数据服务器：

```
ceph-deploy mds create k8s-master2
```

## 安装 RBD  Provisioner

```
cat <<EOF> rbd-provisioner.yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-provisioner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services"]
    resourceNames: ["kube-dns"]
    verbs: ["list", "get"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-provisioner
subjects:
  - kind: ServiceAccount
    name: rbd-provisioner
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: rbd-provisioner
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: Role
metadata:
  name: rbd-provisioner
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: rbd-provisioner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rbd-provisioner
subjects:
- kind: ServiceAccount
  name: rbd-provisioner
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rbd-provisioner
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: rbd-provisioner
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: rbd-provisioner
    spec:
      containers:
      - name: rbd-provisioner
        image: quay.mirrors.ustc.edu.cn/external_storage/rbd-provisioner:latest
        imagePullPolicy: IfNotPresent
        env:
        - name: PROVISIONER_NAME
          value: ceph.com/rbd
      serviceAccount: rbd-provisioner
EOF

kubectl apply -n kube-system -f rbd-provisioner.yaml
```

查看是否已经启动

```
kubectl get pods -l app=rbd-provisioner -n kube-system
```

## Kubernets 挂载外部 ceph

在 ceph 的三台任意一台创建 osd pool

```
ceph osd pool create kube 128
```

创建 secret

```
#获取管理员密钥，替换 secret 中的 key
ceph auth get-key client.admin | base64

#将密钥的 base64 加密替换 key
cat <<EOF> ceph-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret
  namespace: kube-system
data:
  key: QVFDZGJscGI2eURORVJBQXhSTFNYNnR3RVhFZHN3dGE1T1V2QkE9PQ==
type: kubernetes.io/rbd
EOF

kubectl create -f ceph-secret.yaml
```

创建用户的 secret

```
ceph --cluster ceph auth get-or-create client.kube mon 'allow r' osd 'allow rwx pool=kube'
ceph --cluster ceph auth get-key client.kube
ceph auth get-key client.kube | base64

cat <<EOF> ceph-user-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ceph-user-secret
  namespace: default
type: "kubernetes.io/rbd"
data:
  key: QVFDSmMxcGJWZUZ1TnhBQU1VRStlSmlpK2ZwRHFwMzdQY2tlUkE9PQ==
EOF

kubectl create -f ceph-user-secret.yaml
```

创建 storageclass

```
cat <<EOF> ceph-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-rbd
provisioner: ceph.com/rbd
parameters:
  monitors: 10.0.7.102:6789,10.0.7.103:6789,10.0.7.104:6789
  adminId: admin
  adminSecretName: ceph-secret
  adminSecretNamespace: kube-system
  pool: kube
  userId: kube
  userSecretName: ceph-user-secret
  userSecretNamespace: default
  imageFormat: "2"
  imageFeatures: layering
EOF
kubectl create -f ceph-storageclass.yaml
```

创建 pvc

```
cat <<EOF> ceph-pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ceph-claim-dynamic
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: fast-rbd
EOF
kubectl create -f ceph-pvc.yaml
```

创建 pod 测试

```
cat <<EOF> ceph-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ceph-pod1
spec:
  containers:
  - name: ceph-test-pod
    image: nginx
    volumeMounts:
    - name: volume-test
      mountPath: /usr/share/nginx/html
      readOnly: false
  volumes:
  - name: volume-test
    persistentVolumeClaim:
      claimName: ceph-claim-dynamic
EOF

kubectl create -f ceph-test-pod.yaml
```

## 报错解决

当你使用 4.4 内核时，ceph 会出现报错

```
[ 1390.051974] libceph: mon0 10.0.7.102:6789 feature set mismatch, my 106b84a842a42 < server's 40106b84a842a42, missing 400000000000000
[ 1390.053413] libceph: mon0 10.0.7.102:6789 missing required protocol features
```
解决办法，升级内核，或者使用以下命令

```
ceph osd crush tunables hammer
```

挂载 pv 时，ceph 有如下报错：

```
2018-07-27 09:31:10.546814 7f996fa35d40 -1 auth: unable to find a keyring on /etc/ceph/ceph.client.kube.keyring,/etc/ceph/ceph.keyring,/etc/ceph/keyring,/etc/ceph/keyring.bin,: (2) No such file or directory
```


解决办法，kubelet 节点添加 /etc/ceph/keyring 文件

```
cat <<EOF> /etc/ceph/keyring
[client.kube]
    key = AQCJc1pbVeFuNxAAMUE+eJii+fpDqp37PckeRA==
EOF
```

查看是否已经成功挂载

```
[root@k8s-master1 ~]# kubectl exec  -it ceph-pod1 /bin/bash
root@ceph-pod1:/# df -h /usr/share/nginx/html
Filesystem      Size  Used Avail Use% Mounted on
/dev/rbd0       2.0G  6.0M  1.9G   1% /usr/share/nginx/html
```
