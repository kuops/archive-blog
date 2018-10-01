---
title: Kubernetes资源对象之 NameSpace
date: 2018-09-18 21:05:10
categories:
- kubernetes
---


## NameSpace

您可以将 NameSpace 视为 Kubernetes 集群中的虚拟集群。您可以在单个 Kubernetes 集群中拥有多个 NameSpace，并且它们在逻辑上彼此隔离。一个 NameSpace 内的资源名称必须是唯一的。

默认情况下，Kubernetes 初始化时包含以下三个 NameSpace ：

Kubernetes starts with three initial namespaces:

*   `default` 默认的命名空间，用于不属于 kube-public 或 kube-system 命名空间的所有对象。默认命名空间用于保存群集使用的默认 pod，service 和 deployment 。

*   `kube-system` Kubernetes系统创建的资源对象的命名空间
*   `kube-public` 此命名空间是自动创建的，并且可供所有用户（包括未经过身份验证的用户）读取。此命名空间主要用于群集使用，以防某些资源在整个群集中可见且可公开读取。此命名空间的公共方面只是一个约定，而不是一个要求。


### 何时使用 NameSpace

NameSpace 适合用于多个用户分布在多个团队或项目中的环境中。对于具有几个到几十个用户的集群，您不需要创建或考虑 NameSpace。

NameSpace 限制了资源得使用范围，资源名称在 NameSpace 中必须是唯一的，且不能跨名称空间访问。

### 使用 NameSpace

查看命名空间：

```
~$ kubectl get ns
NAME          STATUS    AGE
default       Active    14h
kube-public   Active    14h
kube-system   Active    14h
```

查看 NameSpace 带标签

```
~$ kubectl get ns --show-labels
NAME          STATUS    AGE       LABELS
default       Active    14h       <none>
kube-public   Active    14h       <none>
kube-system   Active    14h       <none>
```

创建 NameSpace

```
kubectl create namespace dev
kubectl create namespace test

cat <<EOF | kubectl create -f -
kind: Namespace
apiVersion: v1
metadata:
  name: prod
  labels:
    name: prod
EOF
```

在 NameSpace 中创建资源：

```
cat <<EOF | kubectl create -f - --namespace=test
apiVersion: v1
kind: Pod
metadata:
  name: mypod
  labels:
    name: mypod
spec:
  containers:
  - name: mypod
    image: nginx
EOF

# 或者在配置文件中声明 namespace

apiVersion: v1
kind: Pod
metadata:
  name: mypod
  namespace: test
  labels:
    name: mypod
spec:
  containers:
  - name: mypod
    image: nginx

```

> 如果在YAML声明中指定命名空间，则将始终在该命名空间中创建资源。如果您尝试使用“namespace”标志来设置另一个命名空间，则该命令将失败。


切换命名空间

```
~$ kubectl config set-context test --namespace=test  --cluster=kubernetes --user=kubernetes-admin

~$ kubectl config use-context test

~$ kubectl get pod
NAME      READY     STATUS    RESTARTS   AGE
mypod     1/1       Running   0          21m
```

### 跨 Namespace 通信

如果要跨 namespace 进行通信，则需要 DNS 服务，Kubernetes 中在创建 Service  时会自动生成 DNS 记录，格式如下

```
<service-name>.<namespace-name>.svc.cluster.local
```

如果要使用 default 空间中得 pod 去访问 test 空间中的 mypod 服务，则使用 `mypod.test` 进行访问

```
kubectl config use-context test
kubectl expose pod mypod  --port=80
kubectl config use-context kubernetes-admin@kubernetes

cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox:1.28
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF

~$ kubectl exec -ti busybox -- nslookup mypod.test
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      mypod.test
Address 1: 10.103.203.253 mypod.test.svc.cluster.local
```
