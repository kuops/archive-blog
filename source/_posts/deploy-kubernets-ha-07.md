---
title: 创建 Kubernetes 集群：配置 bootstrap
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第七部分`
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


## TLS bootstrap

Kubernetes 从 1.4 开始引入了一个API，用于从证书颁发机构（CA）请求证书。此 API 的初衷是为kubelet 启用TLS客户端证书的配置。


## 生成 bootstrap token

bootstrap token 是一种简单的承载令牌，用于在创建新群集或将新节点连接到现有群集时使用。它是为支持 kubeadm 而构建的，但可以在没有 kubeadm 的集群中使用，它可以通过 RBAC 策略与 Kubelet TLS Bootstrapping 系统一起工作。Bootstrap Tokens定义为 `bootstrap.kubernetes.io/token` 存放于 kube-system 命名空间的 secret 资源对象。API服务器中的 Bootstrap Authenticator 会读取这些 Secrets 。使用 Controller Manager 中的 TokenCleaner 控制器删除过期的标记。令牌还用于通过 BootstrapSigner 控制器为 `发现` 过程中使用的特定 ConfigMap 创建签名。

### 令牌格式

Bootstrap令牌采用的形式 `abcdef.0123456789abcdef`。更正式地说，它们必须匹配正则表达式 `[a-z0-9]{6}\.[a-z0-9]{16}`。

令牌的第一部分是 `令牌ID`，并被视为公共信息。用于身份验证。第二部分是 `令牌密钥`，只与受信任方共享。


```
TOKEN_PUB=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
BOOTSTRAP_TOKEN="${TOKEN_PUB}.${TOKEN_SECRET}"

kubectl -n kube-system create secret generic bootstrap-token-${TOKEN_PUB} \
        --type 'bootstrap.kubernetes.io/token' \
        --from-literal description="cluster bootstrap token" \
        --from-literal token-id=${TOKEN_PUB} \
        --from-literal token-secret=${TOKEN_SECRET} \
        --from-literal usage-bootstrap-authentication=true \
        --from-literal usage-bootstrap-signing=true

[root@k8s-master1 ~]# kubectl -n kube-system get secret/bootstrap-token-${TOKEN_PUB} -o yaml
apiVersion: v1
data:
  description: Y2x1c3RlciBib290c3RyYXAgdG9rZW4=
  token-id: MzhkMGM1
  token-secret: ZWJmNGZiYTgyOTI0NjM5NA==
  usage-bootstrap-authentication: dHJ1ZQ==
  usage-bootstrap-signing: dHJ1ZQ==
kind: Secret
metadata:
  creationTimestamp: 2018-07-22T06:17:20Z
  name: bootstrap-token-38d0c5
  namespace: kube-system
  resourceVersion: "835"
  selfLink: /api/v1/namespaces/kube-system/secrets/bootstrap-token-38d0c5
  uid: e407a388-8d76-11e8-b18f-525400c9c704
type: bootstrap.kubernetes.io/token
```

secret 的类型必须是 `bootstrap.kubernetes.io/token`，名称必须是 `bootstrap-token-<token id>`。它也必须存在于 `kube-system` 命名空间中。

`usage-bootstrap-*` 必须将值设置为true启用。

- `usage-bootstrap-authentication` 表示该 token 可用于向 API服务器进行身份验证。

- `usage-bootstrap-signing` 表示该 token 可用于 ConfigMap 签名认证。

## 创建 bootstrap kubeconfig

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="kubelet-bootstrap"
KUBE_CONFIG="bootstrap.kubeconfig"

# 设置集群参数
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置上下文参数
kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${KUBE_USER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置当前使用的上下文
kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 查看生成的配置文件
kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
```

## 配置 configmap

将 bootstrap kubeconfig 和 ca 证书放入 configmap

```
kubectl -n kube-public create configmap cluster-info \
        --from-file /etc/kubernetes/pki/ca.crt \
        --from-file /etc/kubernetes/bootstrap.kubeconfig
```

允许匿名用户访问 configmap
```
kubectl -n kube-public create role system:bootstrap-signer-clusterinfo \
        --verb get --resource configmaps
kubectl -n kube-public create rolebinding kubeadm:bootstrap-signer-clusterinfo \
        --role system:bootstrap-signer-clusterinfo --user system:anonymous
```

## 自动审批


允许 node 节点加入集群
```
kubectl create clusterrolebinding kubeadm:kubelet-bootstrap \
        --clusterrole system:node-bootstrapper --group system:bootstrappers
```

下面的 RBAC ClusterRoles 代表 `nodeclient`，`selfnodeclient` 和 `selfnodeserver` 权限。这些权限可以授予凭证，例如自举令牌。例如，要复制已删除的自动批准标志提供的行为，请批准单个组的所有CSR：

```
cat <<EOF> approve-csr-clusterrole.yaml
# A ClusterRole which instructs the CSR approver to approve a user requesting
# node client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/nodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node renewing its
# own client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
EOF

kubectl create -f approve-csr-clusterrole.yaml
```

将 `system:bootstrappers` 过来的请求，和规则进行绑定

```
cat <<EOF> approve-csr-clusterrolebinding.yaml
# Approve all CSRs for the group "system:bootstrappers"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-csrs-for-group
subjects:
- kind: Group
  name: system:bootstrappers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: approve-node-client-csr
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl create -f approve-csr-clusterrolebinding.yaml
```
