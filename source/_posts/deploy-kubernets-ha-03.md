---
title: 创建 Kubernetes 集群：生成kubeconfig
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第三部分`
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

## 生成 kubeconfig 文件

对于所有访问 API Server 的服务都需要使用 kubeconfig  进行身份验证。在访问 API server 时通过 kubeconfig 带上访问的验证信息，包含(集群，用户和命名空间，和上下文)


### 上下文
在一个 kubeconfig 文件都会有一个上下文件，每个上下文都有三个参数：`cluster` ，`namespace` 和 `user`。

可以使用 `kubectl config use-context` 去设置当前的 `context`。

### KUBECONFIG环境变量

如果 KUBECONFIG 环境变量不存在，则 kubectl使用默认的 kubeconfig 文件 `$HOME/.kube/config`


## service-account 的 kubeconfig

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="system:kube-controller-manager"
KUBE_CERT="sa"
KUBE_CONFIG="controller-manager.kubeconfig"

# 设置集群参数
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置客户端认证参数
kubectl config set-credentials ${KUBE_USER} \
  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
  --embed-certs=true \
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

## kube-scheduler 的 kubeconfig

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="system:kube-scheduler"
KUBE_CERT="kube-scheduler"
KUBE_CONFIG="scheduler.kubeconfig"

# 设置集群参数
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置客户端认证参数
kubectl config set-credentials ${KUBE_USER} \
  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
  --embed-certs=true \
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

## admin 的 kubeconfig

仅留一份在 k8s-master1 节点 ，其他节点如需使用，复制过去即可
```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="admin"
KUBE_CERT="admin"

# 设置集群参数
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \

# 设置客户端认证参数
kubectl config set-credentials ${KUBE_USER} \
  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
  --embed-certs=true \

# 设置上下文参数
kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${KUBE_USER} \

# 设置当前使用的上下文
kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME}

# 查看生成的配置文件
kubectl config view --kubeconfig=$HOME/.kube/config
```

## 分发到其他 master 节点
```
for i in {2..3};do
    scp /etc/kubernetes/*.kubeconfig root@10.0.7.10${i}:/etc/kubernetes
done
```
