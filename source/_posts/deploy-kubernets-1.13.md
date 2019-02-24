---
title: 二进制安装 kubernetes 1.13
date: 2019-02-25 13:31:40
tags:
categories:
- kubernetes
---

适合有基础的观看，没有太详细的说明

## 节点初始化

三个 master 节点，一个 woker 节点

|hostname|os|vip|ip|
|---|---|---|
|k8s-master1|ubuntu|10.0.7.100|10.0.7.101|
|k8s-master2|ubuntu|10.0.7.100|10.0.7.102|
|k8s-master3|ubuntu|10.0.7.100|10.0.7.103|
|k8s-worker1|ubuntu|无|10.0.7.104|

所有节点安装 docke-ce

```
apt-get update

apt-get update && apt-get install apt-transport-https ca-certificates curl software-properties-common -y

# add docker-ce repo
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
  "deb https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  $(lsb_release -cs) \
  stable"

# apt-cache policy docker-ce
apt-get update && apt-get install docker-ce=5:18.09.2~3-0~ubuntu-xenial -y

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://registry.docker-cn.com"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart docker.
systemctl daemon-reload
systemctl restart docker
```

cri 运行需要的依赖
```
modprobe overlay
modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system
```

安装 kubernetes 二进制

```
wget https://storage.googleapis.com/kubernetes-release/release/v1.13.3/kubernetes-server-linux-amd64.tar.gz
tar xf kubernetes-server-linux-amd64.tar.gz
cp kubernetes/server/bin/kube{-apiserver,-controller-manager,-scheduler,ctl,-proxy,let} /usr/local/bin/
```

发送到其他节点
```
scp  -r  /usr/local/bin root@k8s-master2:/usr/local
scp  -r  /usr/local/bin root@k8s-master3:/usr/local
scp  -r  /usr/local/bin root@k8s-worker1:/usr/local
```

## 准备证书

openssl 证书配置文件

```
mkdir -p /etc/kubernetes/pki/etcd
cd /etc/kubernetes/pki

cat <<EOF> /etc/kubernetes/pki/openssl.cnf
[ req ]
default_bits = 2048
default_md = sha256
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

生成 CA 证书

| path | Default CN | description |
| --- | --- | --- |
| ca.crt,key | kubernetes-ca | Kubernetes general CA |
| etcd/ca.crt,key | etcd-ca | For all etcd-related functions |
| front-proxy-ca.crt,key | kubernetes-front-proxy-ca | For the front-end proxy |


kubernetes-ca

```
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -config openssl.cnf -subj "/CN=kubernetes-ca" -extensions v3_ca -out ca.crt -days 10000
```
etcd-ca

```
openssl genrsa -out etcd/ca.key 2048
openssl req -x509 -new -nodes -key etcd/ca.key -config openssl.cnf -subj "/CN=etcd-ca" -extensions v3_ca -out etcd/ca.crt -days 10000
```

front-proxy-ca

```
openssl genrsa -out front-proxy-ca.key 2048
openssl req -x509 -new -nodes -key front-proxy-ca.key -config openssl.cnf -subj "/CN=kubernetes-ca" -extensions v3_ca -out front-proxy-ca.crt -days 10000
```


生成所有的证书

| Default CN | Parent CA | O (in Subject) | kind | 
| --- | --- | --- | --- | --- |
| kube-etcd | etcd-ca || server, client |
| kube-etcd-peer | etcd-ca || server, client |
| kube-etcd-healthcheck-client | etcd-ca || client |
| kube-apiserver-etcd-client | etcd-ca | system:masters | client |
| kube-apiserver | kubernetes-ca || server |
| kube-apiserver-kubelet-client | kubernetes-ca | system:masters | client |
| front-proxy-client | kubernetes-front-proxy-ca || client |


证书路径

| Default CN | recommend key path | recommended cert path | command | key argument | cert argument |
| --- | --- | --- | --- | --- | --- |
| etcd-ca || etcd/ca.crt | kube-apiserver | |–etcd-cafile |
| etcd-client | apiserver-etcd-client.key | apiserver-etcd-client.crt | kube-apiserver | –etcd-keyfile | –etcd-certfile |
| kubernetes-ca || ca.crt | kube-apiserver || –client-ca-file |
| kube-apiserver | apiserver.key | apiserver.crt | kube-apiserver | –tls-private-key-file | –tls-cert-file |
| apiserver-kubelet-client || apiserver-kubelet-client.crt | kube-apiserver || –kubelet-client-certificate |
| front-proxy-ca || front-proxy-ca.crt | kube-apiserver || –requestheader-client-ca-file |
| front-proxy-client | front-proxy-client.key | front-proxy-client.crt | kube-apiserver | –proxy-client-key-file | –proxy-client-cert-file |
| etcd-ca || etcd/ca.crt | etcd || –trusted-ca-file, –peer-trusted-ca-file |
| kube-etcd | etcd/server.key | etcd/server.crt | etcd | –key-file | –cert-file |
| kube-etcd-peer | etcd/peer.key | etcd/peer.crt | etcd | –peer-key-file | –peer-cert-file |
| etcd-ca || etcd/ca.crt | etcdctl || –cacert |
| kube-etcd-healthcheck-client | etcd/healthcheck-client.key | etcd/healthcheck-client.crt | etcdctl | –key | –cert |


生成证书

apiserver-etcd-client

```
openssl genrsa -out apiserver-etcd-client.key 2048
openssl req -new -key apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client/O=system:masters" -out apiserver-etcd-client.csr
openssl x509 -in apiserver-etcd-client.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out apiserver-etcd-client.crt -days 10000
```

kube-etcd

```
openssl genrsa -out etcd/server.key 2048
openssl req -new -key etcd/server.key -subj "/CN=etcd-server" -out etcd/server.csr
openssl x509 -in etcd/server.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/server.crt -days 10000
```

kube-etcd-peer

```
openssl genrsa -out etcd/peer.key 2048
openssl req -new -key etcd/peer.key -subj "/CN=etcd-peer" -out etcd/peer.csr
openssl x509 -in etcd/peer.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/peer.crt -days 10000
```

kube-etcd-healthcheck-client

```
openssl genrsa -out etcd/healthcheck-client.key 2048
openssl req -new -key etcd/healthcheck-client.key -subj "/CN=etcd-client" -out etcd/healthcheck-client.csr
openssl x509 -in etcd/healthcheck-client.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/healthcheck-client.crt -days 10000
```

kube-apiserver

```
openssl genrsa -out apiserver.key 2048
openssl req -new -key apiserver.key -subj "/CN=kube-apiserver" -config openssl.cnf -out apiserver.csr
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_apiserver -extfile openssl.cnf -out apiserver.crt
```

apiserver-kubelet-client

```
openssl genrsa -out  apiserver-kubelet-client.key 2048
openssl req -new -key apiserver-kubelet-client.key -subj "/CN=apiserver-kubelet-client/O=system:masters" -out apiserver-kubelet-client.csr
openssl x509 -req -in apiserver-kubelet-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out apiserver-kubelet-client.crt
```

front-proxy-client

```
openssl genrsa -out  front-proxy-client.key 2048
openssl req -new -key front-proxy-client.key -subj "/CN=front-proxy-client" -out front-proxy-client.csr
openssl x509 -req -in front-proxy-client.csr -CA front-proxy-ca.crt -CAkey front-proxy-ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out front-proxy-client.crt
```

kube-scheduler 证书
```
openssl genrsa -out  kube-scheduler.key 2048
openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out kube-scheduler.crt
```

sa.pub sa.key

```
openssl genrsa -out  sa.key 2048
openssl ecparam -name secp521r1 -genkey -noout -out sa.key
openssl ec -in sa.key -outform PEM -pubout -out sa.pub
openssl req -new -sha256 -key sa.key -subj "/CN=system:kube-controller-manager" -out sa.csr
openssl x509 -req -in sa.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out sa.crt
```

admin 证书

```
openssl genrsa -out  admin.key 2048
openssl req -new -key admin.key -subj "/CN=kubernetes-admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out admin.crt
```

清理 csr srl

```
find . -name "*.csr" -o -name "*.srl"|xargs  rm -f
```


## 准备 kubeconfig


| filename | credential name | Default CN | O (in Subject) |
| --- | --- | --- | --- |
| admin.conf | default-admin | kubernetes-admin | system:masters |
| controller-manager.conf | default-controller-manager | system:kube-controller-manager ||
| scheduler.conf | default-manager | system:kube-scheduler ||


kube-controller-manager

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="system:kube-controller-manager"
KUBE_CERT="sa"
KUBE_CONFIG="controller-manager.conf"

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

kube-scheduler

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="system:kube-scheduler"
KUBE_CERT="kube-scheduler"
KUBE_CONFIG="scheduler.conf"

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

admin

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_USER="kubernetes-admin"
KUBE_CERT="admin"
KUBE_CONFIG="admin.conf"

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


## 分发证书

分发到 config 及证书其他 master 节点

```
scp  -r /etc/kubernetes root@k8s-master2:/etc
scp  -r /etc/kubernetes root@k8s-master3:/etc
```

## 配置 HA 

master 节点，配置 envoy

```
mkdir -p /etc/envoy
cat <<EOF> /etc/envoy/envoy.yaml
static_resources:
  listeners:
  - address:
      socket_address:
        address: 0.0.0.0
        port_value: 8443
    filter_chains:
    - filters:
      - name: envoy.tcp_proxy
        config:
          stat_prefix: ingress_tcp
          cluster: kube_apiserver
          access_log:
            - name: envoy.file_access_log
              config:
                path: /dev/stdout
  clusters:
  - name: kube_apiserver
    connect_timeout: 0.25s
    type: strict_dns
    lb_policy: round_robin
    hosts:
    - socket_address:
        address: 10.0.7.101
        port_value: 6443
    - socket_address:
        address: 10.0.7.102
        port_value: 6443
    - socket_address:
        address: 10.0.7.103
        port_value: 6443

admin:
  access_log_path: "/dev/null"
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 8001
EOF
```

envoy unit file

```
cat<<EOF> /lib/systemd/system/envoy.service
[Unit]
Description=Envoy Container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop %n
ExecStartPre=-/usr/bin/docker rm %n
ExecStartPre=/usr/bin/docker pull envoyproxy/envoy:latest
ExecStart=/usr/bin/docker run --rm -v /etc/envoy/envoy.yaml:/etc/envoy/envoy.yaml --network host --name %n envoyproxy/envoy:latest

[Install]
WantedBy=multi-user.target
EOF

systemctl restart envoy.service
systemctl enable envoy.service
systemctl status envoy.service -l
```

master 配置 keepalived

```
apt-get install keepalived -y
```

keepalived 健康检查脚本

```
cat <<'EOF'> /etc/keepalived/ha_check.sh
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

keepalived 配置文件

```
cat <<EOF> /etc/keepalived/keepalived.conf
vrrp_script ha-check {
    script "/bin/bash /etc/keepalived/ha_check.sh"
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance k8s-vip {
    state BACKUP
    priority 101
    interface enp0s8
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

systemctl restart  keepalived.service
systemctl enable  keepalived.service
```

## 配置 etcd

安装 etcd 二进制

```
mkdir -p /var/lib/etcd
ETCD_VER=v3.3.10
wget https://storage.googleapis.com/etcd/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xf etcd-${ETCD_VER}-linux-amd64.tar.gz  --strip-components=1 -C /usr/local/bin etcd-${ETCD_VER}-linux-amd64/{etcd,etcdctl}
mkdir -p /usr/lib/systemd/system/
```

设置 unit file 并启动 etcd,其他节点修改对应 ETCD_NAME 为 etcd1 和 etcd2，ip 改为节点 IP。

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
    --cert-file=/etc/kubernetes/pki/etcd/server.crt \\
    --key-file=/etc/kubernetes/pki/etcd/server.key \\
    --client-cert-auth \\
    --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt \\
    --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt \\
    --peer-key-file=/etc/kubernetes/pki/etcd/peer.key \\
    --peer-client-cert-auth \\
    --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt \\
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

检查 

```
etcdctl \
 --cert-file /etc/kubernetes/pki/etcd/healthcheck-client.crt \
 --key-file /etc/kubernetes/pki/etcd/healthcheck-client.key \
 --ca-file /etc/kubernetes/pki/etcd/ca.crt \
 --endpoints https://10.0.7.101:2379 cluster-health
```

## 配置 master 组件

启动 api-server

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
  --enable-admission-plugins=Initializers,DefaultStorageClass,DefaultTolerationSeconds,LimitRanger,NamespaceLifecycle,NodeRestriction,PersistentVolumeClaimResize,ResourceQuota,ServiceAccount,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,Priority \\
  --advertise-address=${NODE_IP} \\
  --bind-address=${NODE_IP}  \\
  --insecure-port=0 \\
  --secure-port=6443 \\
  --allow-privileged=true \\
  --apiserver-count=1 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --enable-swagger-ui=true \\
  --storage-backend=etcd3 \\
  --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \\
  --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt \\
  --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key \\
  --etcd-servers=https://10.0.7.101:2379,https://10.0.7.102:2379,https://10.0.7.103:2379 \\
  --event-ttl=1h \\
  --enable-bootstrap-token-auth \\
  --client-ca-file=/etc/kubernetes/pki/ca.crt \\
  --kubelet-https \\
  --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key \\
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
  --runtime-config=api/all \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --service-node-port-range=30000-32767 \\
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \\
  --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \\
  --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \\
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

启动 controller-manager

```
cat<<EOF> /usr/lib/systemd/system/kube-controller-manager.service 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --allocate-node-cidrs=true \\
  --kubeconfig=/etc/kubernetes/controller-manager.conf \\
  --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf \\
  --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf \\
  --client-ca-file=/etc/kubernetes/pki/ca.crt \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca.key \\
  --bind-address=127.0.0.1 \\
  --leader-elect=true \\
  --cluster-cidr=10.244.0.0/16 \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \\
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \\
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

启动 scheduler

```
cat > /usr/lib/systemd/system/kube-scheduler.service << EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --kubeconfig=/etc/kubernetes/scheduler.conf \\
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

验证组件是否正常

```
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get cs
```

## 配置 bootstrap

设置 bootstrap , 创建 bootstrap 令牌
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
```

创建 bootstrap kubeconfig 文件

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.101:6443"
KUBE_USER="kubelet-bootstrap"
KUBE_CONFIG="bootstrap.conf"

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

# 设置客户端认证参数
kubectl config set-credentials ${KUBE_USER} \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置当前使用的上下文
kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 查看生成的配置文件
kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
```

授权 kubelet 可以创建 csr
```
kubectl create clusterrolebinding kubeadm:kubelet-bootstrap \
        --clusterrole system:node-bootstrapper --group system:bootstrappers
```

批准 csr 请求

> 允许 system:bootstrappers 组的所有 csr

```
cat <<EOF | kubectl apply -f -
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
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
  apiGroup: rbac.authorization.k8s.io
EOF
```

允许 kubelet 能够更新自己的证书

```
cat <<EOF | kubectl apply -f -
# Approve renewal CSRs for the group "system:nodes"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-renewals-for-nodes
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
  apiGroup: rbac.authorization.k8s.io
EOF
```

创建所需的 clusterrole

```
cat <<EOF | kubectl apply -f -
# A ClusterRole which instructs the CSR approver to approve a user requesting
# node client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
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
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeclient"]
  verbs: ["create"]
EOF
```

## 配置 worker 组件

将 ca.crt 和  bootstrap.conf 发送至需要运行 worker 的节点

```
mkdir -p /etc/kubernetes/pki
scp root@k8s-master1:/etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/ca.crt
scp root@k8s-master1:/etc/kubernetes/bootstrap.conf /etc/kubernetes/bootstrap.conf
```

kubelet 的 yaml 配置文件

```
mkdir -p /var/lib/kubelet/
cat <<EOF> /var/lib/kubelet/config.yaml
address: 0.0.0.0
apiVersion: kubelet.config.k8s.io/v1beta1
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
cgroupDriver: systemd
cgroupsPerQOS: true
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
configMapAndSecretChangeDetectionStrategy: Watch
containerLogMaxFiles: 5
containerLogMaxSize: 10Mi
contentType: application/vnd.kubernetes.protobuf
cpuCFSQuota: true
cpuCFSQuotaPeriod: 100ms
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
kind: KubeletConfiguration
kubeAPIBurst: 10
kubeAPIQPS: 5
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeLeaseDurationSeconds: 40
nodeStatusReportFrequency: 1m0s
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
port: 10250
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

启动 kubelet 

```
mkdir -p /usr/lib/systemd/system
mkdir -p /etc/kubernetes/manifests
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.conf \\
  --kubeconfig=/etc/kubernetes/kubelet.conf \\
  --config=/var/lib/kubelet/config.yaml \\
  --cgroup-driver=systemd \\
  --pod-infra-container-image=kuops/pause-amd64:3.1 \\
  --allow-privileged=true \\
  --network-plugin=cni \\
  --cni-conf-dir=/etc/cni/net.d \\
  --cni-bin-dir=/opt/cni/bin \\
  --cert-dir=/etc/kubernetes/pki \\
  --v=2

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

创建 kube-proxy 的 serviceaccount
```
kubectl -n kube-system create serviceaccount kube-proxy
```

创建 kube-proxy 的 cluster rolebinding
```
kubectl create clusterrolebinding kubeadm:node-proxier \
        --clusterrole system:node-proxier \
        --serviceaccount kube-system:kube-proxy
```

创建 kube-proxy 的 kubeconfig

```
CLUSTER_NAME="kubernetes"
KUBE_APISERVER="https://10.0.7.100:8443"
KUBE_CONFIG="kube-proxy.conf"

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
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

kubectl config set-credentials ${CLUSTER_NAME} \
  --token=${JWT_TOKEN} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

kubectl config use-context ${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
```

其他节点拉取

```
scp root@k8s-master1:/etc/kubernetes/kube-proxy.conf /etc/kubernetes/kube-proxy.conf
```

kube-proxy 的 yaml 配置

```
mkdir -p /var/lib/kube-proxy
cat <<EOF> /var/lib/kube-proxy/config.conf
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
clientConnection:
    acceptContentTypes: ""
    burst: 10
    contentType: application/vnd.kubernetes.protobuf
    kubeconfig: /etc/kubernetes/kube-proxy.conf
    qps: 5
clusterCIDR: "10.244.0.0/16"
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
    masqueradeAll: true
    masqueradeBit: 14
    minSyncPeriod: 0s
    syncPeriod: 30s
ipvs:
    excludeCIDRs: null
    minSyncPeriod: 0s
    scheduler: ""
    syncPeriod: 30s
kind: KubeProxyConfiguration
metricsBindAddress: 127.0.0.1:10249
mode: "iptables"
nodePortAddresses: null
oomScoreAdj: -999
portRange: ""
resourceContainer: /kube-proxy
udpIdleTimeout: 250ms
EOF
```

启动 kube-proxy

```
mkdir /var/lib/kube-proxy

cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/config.conf \\
  --conntrack-max=0 \\
  --conntrack-max-per-core=0 \\
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

## 节点标签

```
kubectl label node k8s-master1 node-role.kubernetes.io/master=""
kubectl label node k8s-master2 node-role.kubernetes.io/master=""
kubectl label node k8s-master3 node-role.kubernetes.io/master=""
kubectl label node k8s-worker1 node-role.kubernetes.io/worker=worker
```

## 安装 flannel

安装 cni

```
curl -LO https://github.com/containernetworking/plugins/releases/download/v0.7.4/cni-plugins-amd64-v0.7.4.tgz
mkdir -p /opt/cni/bin
tar -xf cni-plugins-amd64-v0.7.4.tgz -C /opt/cni/bin
```

安装 flannel

```
cat <<EOF> kube-flannel.yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: psp.flannel.unprivileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default
    seccomp.security.alpha.kubernetes.io/defaultProfileName: docker/default
    apparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default
    apparmor.security.beta.kubernetes.io/defaultProfileName: runtime/default
spec:
  privileged: false
  volumes:
    - configMap
    - secret
    - emptyDir
    - hostPath
  allowedHostPaths:
    - pathPrefix: "/etc/cni/net.d"
    - pathPrefix: "/etc/kube-flannel"
    - pathPrefix: "/run/flannel"
  readOnlyRootFilesystem: false
  # Users and groups
  runAsUser:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  # Privilege Escalation
  allowPrivilegeEscalation: false
  defaultAllowPrivilegeEscalation: false
  # Capabilities
  allowedCapabilities: ['NET_ADMIN']
  defaultAddCapabilities: []
  requiredDropCapabilities: []
  # Host namespaces
  hostPID: false
  hostIPC: false
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  # SELinux
  seLinux:
    # SELinux is unsed in CaaSP
    rule: 'RunAsAny'
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
rules:
  - apiGroups: ['extensions']
    resources: ['podsecuritypolicies']
    verbs: ['use']
    resourceNames: ['psp.flannel.unprivileged']
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes/status
    verbs:
      - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-system
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-amd64
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: amd64
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: kuopsquay/coreos.flannel:v0.11.0-amd64
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: kuopsquay/coreos.flannel:v0.11.0-amd64
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        - --iface=enp0s8
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
EOF


kubectl apply -f kube-flannel.yaml
```

## 安装 coredns

```
cat <<EOF> coredns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
  labels:
      kubernetes.io/cluster-service: "true"
      addonmanager.kubernetes.io/mode: Reconcile
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: Reconcile
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: EnsureExists
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
  labels:
      addonmanager.kubernetes.io/mode: EnsureExists
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            upstream
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  # replicas: not specified here:
  # 1. In order to make Addon Manager do not reconcile this replicas parameter.
  # 2. Default is 1.
  # 3. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
      annotations:
        seccomp.security.alpha.kubernetes.io/pod: 'docker/default'
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        beta.kubernetes.io/os: linux
      containers:
      - name: coredns
        image: coredns/coredns:1.3.1
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF
```
