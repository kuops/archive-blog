---
title: 创建 Kubernetes 集群：配置 Flannel 和 CoreDNS
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第十部分`
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

## 安装 CNI 插件

关于 CNI 的版本可以查询 https://github.com/kubernetes/kubernetes/blob/master/build/debian-hyperkube-base/Makefile

```
mkdir -p /opt/cni/bin
CNI_VER="v0.6.0"
curl -sSLO --retry 5 https://storage.googleapis.com/kubernetes-release/network-plugins/cni-plugins-amd64-${CNI_VER}.tgz
tar -xf cni-plugins-amd64-${CNI_VER}.tgz -C /opt/cni/bin

for i in {2..4};do
    scp -r /opt/cni 10.0.7.10${i}:/opt
done
```

## 安装 flannel

```
curl -sSL https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml > kube-flannel.yml
sed -i 's@quay.io/coreos/@kuopsquay/coreos.@g' kube-flannel.yml
sed -i '/kube-subnet-mgr/a\        - --iface=eth1' kube-flannel.yml
sed -i 's@vxlan@host-gw@g' kube-flannel.yml
kubectl apply -f kube-flannel.yml
```

## 安装 CoreDNS

```
cat <<EOF> coredns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
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
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
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
        proxy . /etc/resolv.conf
        cache 30
        reload
        loadbalance
    }
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 2
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
    spec:
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      containers:
      - name: coredns
        image: coredns/coredns:1.2.0
        imagePullPolicy: IfNotPresent
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
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
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
EOF
kubectl  create  -f coredns.yaml
```
验证 DNS , 创建测试 pod
```
cat > dns-test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: curl
  namespace: default
spec:
  containers:
  - image: appropriate/curl
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
  restartPolicy: Always
EOF

kubectl create -f dns-test-pod.yaml 

# 创建 测试 service
kubectl create deployment nginx  --image=nginx
kubectl  expose deployment nginx --port=80 --target-port=80
```
测试

```
[root@k8s-master1 ~]# kubectl exec -ti curl -- ping nginx
PING nginx (10.96.42.69): 56 data bytes

[root@k8s-master1 ~]# kubectl exec -ti curl -- curl nginx -I
HTTP/1.1 200 OK
Server: nginx/1.15.1
Date: Mon, 23 Jul 2018 02:30:37 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 03 Jul 2018 13:27:08 GMT
Connection: keep-alive
ETag: "5b3b79ac-264"
Accept-Ranges: bytes
```
