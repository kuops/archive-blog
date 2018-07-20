---
title: 创建 Kubernetes 集群：生成证书
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第二部分`
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

## 证书列表

准备证书列表：

> - **kubernetes CA 机构证书及私钥：** ca.crt ca.key

> - **etcd-server 证书及私钥：** etcd-server.crt etcd-server.key

> - **etcd-peer 证书及私钥：** etcd-peer.crt etcd-peer.key

> - **etcd-client 证书及私钥：** etcd-client.crt etcd-client.key

> - **kube-apiserver 证书及私钥：** kube-apiserver.crt  kube-apiserver.key

> - **apiserver-kubelet-client 证书及私钥：** apiserver-kubelet-client.crt apiserver-kubelet-client.key

> - **service-account 的公钥和私钥：** sa.pub sa.key

> - **kube-scheduler 的证书及私钥：** kube-scheduler.crt kube-scheduler.key

> - **kube-proxy 的证书及私钥：** kube-proxy.crt kube-proxy.key

> - **front-proxy-ca 的证书及私钥：** front-proxy-ca.crt front-proxy-ca.key

> - **front-proxy-client 的证书及私钥：** front-proxy-client.crt front-proxy-client.key

> - **admin 管理员证书及私钥：** admin.crt admin.key


## 准备 opensl 配置文件

进入 kubernets 的证书目录
```
cd /etc/kubernetes/pki
```

准备 openssl.conf
```
cat <<EOF> /etc/kubernetes/pki/openssl.cnf
[ req ]
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_ca ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign
[ v3_req_server ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[ v3_req_client ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
[ v3_req_apiserver ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names_cluster
[ v3_req_etcd ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names_etcd
[ alt_names_cluster ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = k8s-master1
DNS.6 = k8s-master2
DNS.7 = k8s-master3
DNS.8 = localhost
IP.1 = 10.96.0.1
IP.2 = 127.0.0.1
IP.3 = 10.0.7.100
IP.4 = 10.0.7.101
IP.5 = 10.0.7.102
IP.6 = 10.0.7.103
[ alt_names_etcd ]
DNS.1 = localhost
IP.1 = 10.0.7.101
IP.2 = 10.0.7.102
IP.3 = 10.0.7.103
IP.4 = 127.0.0.1
EOF
```

## 根（CA）证书

准备 kubernetes CA  证书，证书的颁发机构名称为 `kubernets`：

> 用于签署其它的 K8s 证书。

```
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -config openssl.cnf -subj "/CN=kubernetes" -extensions v3_ca -out ca.crt -days 10000
```

## ETCD 证书

准备 etcd-server 证书：

> 用于 etcd 客户端和服务器之间通信的证书

```
openssl genrsa -out etcd-server.key 2048
openssl req -new -key etcd-server.key -subj "/CN=etcd-server" -out etcd-server.csr
openssl x509 -in etcd-server.csr -req -CA ca.crt -CAkey ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd-server.crt -days 10000
```

准备 etcd-peer 证书

> 用于 etcd 服务器和服务器之间通信的证书

```
openssl genrsa -out etcd-peer.key 2048
openssl req -new -key etcd-peer.key -subj "/CN=etcd-peer" -out etcd-peer.csr
openssl x509 -in etcd-peer.csr -req -CA ca.crt -CAkey ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd-peer.crt -days 10000
```

准备 etcd-client 证书

> 用于 etcd 客户端使用的证书

```
openssl genrsa -out etcd-client.key 2048
openssl req -new -key etcd-client.key -subj "/CN=etcd-client" -out etcd-client.csr
openssl x509 -in etcd-client.csr -req -CA ca.crt -CAkey ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd-client.crt -days 10000
```

## Kubernets 组件证书

准备 kube-apiserver 证书：

> 用于 kube-apiserver 的证书

```
openssl genrsa -out kube-apiserver.key 2048
openssl req -new -key kube-apiserver.key -subj "/CN=kube-apiserver" -config openssl.cnf -out kube-apiserver.csr
openssl x509 -req -in kube-apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_apiserver -extfile openssl.cnf -out kube-apiserver.crt
```

准备 apiserver-kubelet-client 证书：

> 用于 apiserver 对 kubelet 的进行客户端身份验证

```
openssl genrsa -out  apiserver-kubelet-client.key 2048
openssl req -new -key apiserver-kubelet-client.key -subj "/CN=apiserver-kubelet-client/O=system:masters" -out apiserver-kubelet-client.csr
openssl x509 -req -in apiserver-kubelet-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out apiserver-kubelet-client.crt
```

准备 service account 私钥：

> service account token 的私钥仅提供给 controller-manager 使用。controller-manager 通过 `sa.key` 对 token 进行签名。
master 节点通过公钥 `sa.pub` 进行验证签名。

```
openssl genrsa -out  sa.key 2048
openssl ecparam -name secp521r1 -genkey -noout -out sa.key
openssl ec -in sa.key -outform PEM -pubout -out sa.pub
openssl req -new -sha256 -key sa.key -subj "/CN=system:kube-controller-manager" -out sa.csr
openssl x509 -req -in sa.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out sa.crt
```

准备 kube-scheduler 证书：

> 允许访问 kube-scheduler 组件所需的资源。

```
openssl genrsa -out  kube-scheduler.key 2048
openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out kube-scheduler.crt
```

准备 kube-proxy 证书

> 仅当您要使用 kube-proxy role 而不是具有JWT(json web token)令牌（kubernetes secrets）的 kube-proxy 服务帐户进行身份验证时，才创建 kube-proxy 证书。

```
openssl genrsa -out  kube-proxy.key 2048
openssl req -new -key kube-proxy.key -subj "/CN=kube-proxy/O=system:node-proxier" -out kube-proxy.csr
openssl x509 -req -in kube-proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out kube-proxy.crt
```

准备 front-proxy-ca 证书


```
openssl genrsa -out  front-proxy-ca.key 2048
openssl req -x509 -new -nodes -key front-proxy-ca.key -config openssl.cnf -subj "/CN=front-proxy-ca" -extensions v3_ca  -config openssl.cnf  -out front-proxy-ca.crt -days 10000
```


准备 front-proxy-client 证书

> 用于将指定的 header 中的用户名之前验证传入请求的客户端证书 `--requestheader-username-headers`

```
openssl genrsa -out  front-proxy-client.key 2048
openssl req -new -key front-proxy-client.key -subj "/CN=front-proxy-client" -out front-proxy-client.csr
openssl x509 -req -in front-proxy-client.csr -CA front-proxy-ca.crt -CAkey front-proxy-ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out front-proxy-client.crt
```


## 集群管理员证书

准备  admin 管理员证书：

> 管理员访问 kubernets 资源的证书

```
openssl genrsa -out  admin.key 2048
openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out admin.crt
```

## 分发证书

清理 csr 文件，并分发证书到其他 master 节点

```
rm *.csr -f
for i in {2..3};do
    scp -rp /etc/kubernetes/pki root@10.0.7.10${i}:/etc/kubernetes
done
```




