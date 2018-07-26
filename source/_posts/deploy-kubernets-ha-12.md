---
title: 创建 Kubernetes 集群：配置 traefik
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本篇文章为创建 Kubernets 集群 `第十二部分`
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

## traefk

将Træfik用作Kubernetes集群的Ingress控制器。

## 设置 rbac 授权

允许 traefik 访问集群中的资源

```
cat <<EOF> traefik-rbac.yaml
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
- kind: ServiceAccount
  name: traefik-ingress-controller
  namespace: kube-system
EOF

kubectl apply -f traefik-rbac.yaml
```

## 创建 configmap

trafik 的配置文件

```
cat <<EOF> traefik-configmap.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kube-system
  name: traefik-conf
data:
  traefik.toml: |
    # traefik.toml
    logLevel = "DEBUG"
    defaultEntryPoints = ["http","https"]
    [entryPoints]
      [entryPoints.http]
      address = ":80"
      [entryPoints.http.redirect]
      #entryPoint = "https"
      [entryPoints.https]
      address = ":443"
      [entryPoints.https.tls]
      [[entryPoints.https.tls.certificates]]
      CertFile = "/ssl/tls.crt"
      KeyFile = "/ssl/tls.key"
    [kubernetes]
    [web]
    address = ":8080"
      [web.auth.basic]
        users = ["admin:$apr1$ehrsakXa$zr4qevnn4t.gOV7J8Ia/y1"]
EOF
kubectl apply -f traefik-configmap.yaml
```

## 设置 secret

生成证书，并创建 secret

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=*.k8s.kuops.com"
kubectl -n kube-system create secret tls traefik-cert --key=tls.key --cert=tls.crt
```

## 配置 deployment

traefik 的 deployment

```
cat <<EOF> traefik-deployment.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik-ingress-controller
  namespace: kube-system
---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: traefik-ingress-controller
  namespace: kube-system
  labels:
    k8s-app: traefik-ingress-lb
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: traefik-ingress-lb
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress-lb
        name: traefik-ingress-lb
    spec:
      serviceAccountName: traefik-ingress-controller
      terminationGracePeriodSeconds: 60
      containers:
      - image: traefik
        name: traefik-ingress-lb
        ports:
        - name: http
          containerPort: 80
        - name: https
          containerPort: 443
        - name: admin
          containerPort: 8080
        volumeMounts:
        - mountPath: /etc/traefik
          name: traefik-config
        - mountPath: "/ssl"
          name: "ssl"
        args:
        - --web
        - --configfile=/etc/traefik/traefik.toml
        - --api
        - --kubernetes
        - --logLevel=INFO
      volumes:
      - name: traefik-config
        configMap:
          name: traefik-conf
      - name: ssl
        secret:
          secretName: traefik-cert
---
kind: Service
apiVersion: v1
metadata:
  name: traefik-ingress-service
  namespace: kube-system
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - protocol: TCP
      port: 80
      name: web
    - protocol: TCP
      port: 443
      name: https
    - protocol: TCP
      port: 8080
      name: admin
  type: NodePort
EOF

kubectl apply -f traefik-deployment.yaml
```

## 配置 haproxy

将 traefik 的 nodeport 添加到 vip 的后端节点，通过 vip 访问 ingress

```
cat <<EOF> /etc/haproxy/haproxy.cfg
global
  maxconn  2000
  ulimit-n  16384
  log  127.0.0.1 local0 err
  stats timeout 30s

defaults
  log global
  mode  http
  option  httplog
  timeout connect 5000
  timeout client  50000
  timeout server  50000
  timeout http-request 15s
  timeout http-keep-alive 15s

frontend monitor-in
  bind *:33305
  mode http
  option httplog
  monitor-uri /monitor

listen stats
  bind    *:8006
  mode    http
  stats   enable
  stats   hide-version
  stats   uri       /stats
  stats   refresh   30s
  stats   realm     Haproxy\ Statistics
  stats   auth      admin:admin

frontend k8s-api
  bind 0.0.0.0:8443
  bind 127.0.0.1:8443
  mode tcp
  option tcplog
  tcp-request inspect-delay 5s
  default_backend k8s-api

backend k8s-api
  mode tcp
  option tcplog
  option tcp-check
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
  server k8s-api-1 10.0.7.101:6443 check
  server k8s-api-2 10.0.7.102:6443 check
  server k8s-api-3 10.0.7.103:6443 check

frontend traefik-http
  bind 0.0.0.0:80
  bind 127.0.0.1:80
  mode tcp
  option tcplog
  tcp-request inspect-delay 5s
  default_backend traefik-http

#对应 80 端口的 nodeport
backend traefik-http
  mode tcp
  option tcplog
  option tcp-check
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
  server traefik-nodeport-1 10.0.7.101:30949 check
  server traefik-nodeport-2 10.0.7.102:30949 check
  server traefik-nodeport-3 10.0.7.103:30949 check

frontend traefik-https
  bind 0.0.0.0:443
  bind 127.0.0.1:443
  mode tcp
  option tcplog
  tcp-request inspect-delay 5s
  default_backend traefik-https

#对应 443 端口的 nodeport
backend traefik-https
  mode tcp
  option tcplog
  option tcp-check
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
  server traefik-https-1 10.0.7.101:31020 check
  server traefik-https-2 10.0.7.102:31020 check
  server traefik-https-3 10.0.7.103:31020 check
EOF
```

## 测试

将 traefik-ui 暴露出来

```
cat <<EOF> traefik-ui-ingress.yaml
apiVersion: v1
kind: Service
metadata:
  name: traefik-web-ui
  namespace: kube-system
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: traefik-web-ui
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: traefik-ui.k8s.kuops.com
    http:
      paths:
      - backend:
          serviceName: traefik-web-ui
          servicePort: 80
  tls:
   - secretName: traefik-cert
EOF
kubectl create -f traefik-ui-ingress.yaml
```

修改 /etc/hosts 文件，添加访问

```
[root@k8s-master1 ~]# curl  -k https://traefik-ui.ingress.traefik
<a href="/dashboard/">Found</a>.
```
