---
title: 创建 Kubernetes 集群：配置 Promethus-Operater
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第十四部分`
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

## prometheus-operator

prometheus-operator 简化了 kubernets 集群的 service 和 deployment 的监控，和 prometheus 实例的管理。

安装后，Prometheus Operator 提供以下功能：

- 创建/销毁：使用 Operator 能轻松的启动 prometheus 实例，使用 Operator 监控特定的应用

- 简单配置：配置跟原生 prometheus 保持一致

- 通过标签生成配置：基于 Kubernetes 标签查询自动生成监视目标配置；不需要学习 Prometheus 特定的配置语言。


## 配置 prometheus-operator

设置 prometheus-operator 的 rbac 权限，及创建 deployment

```
cat <<EOF> bundle.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:    
  name: prometheus-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-operator
subjects:
- kind: ServiceAccount
  name: prometheus-operator
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-operator
rules:
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - '*'
- apiGroups:
  - monitoring.coreos.com
  resources:
  - alertmanagers
  - prometheuses
  - prometheuses/finalizers
  - alertmanagers/finalizers
  - servicemonitors
  - prometheusrules
  verbs:
  - '*'
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - '*'
- apiGroups:
  - ""
  resources:
  - configmaps
  - secrets
  verbs:
  - '*'
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
  - delete
- apiGroups:
  - ""
  resources:
  - services
  - endpoints
  verbs:
  - get
  - create
  - update
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
  - namespaces
  verbs:
  - list
  - watch
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  labels:
    k8s-app: prometheus-operator
  name: prometheus-operator
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: prometheus-operator
  template:
    metadata:
      labels:
        k8s-app: prometheus-operator
    spec:
      containers:
      - args:
        - --kubelet-service=kube-system/kubelet
        - -logtostderr=true
        - --config-reloader-image=kuopsquay/coreos.configmap-reload:v0.0.1
        - --prometheus-config-reloader=kuopsquay/coreos.prometheus-config-reloader:v0.22.0
        image: kuopsquay/coreos.prometheus-operator:v0.22.0
        name: prometheus-operator
        ports:
        - containerPort: 8080
          name: http
        resources:
          limits:
            cpu: 200m
            memory: 100Mi
          requests:
            cpu: 100m
            memory: 50Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      serviceAccountName: prometheus-operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-operator
  namespace: default
EOF
kubectl apply -f bundle.yaml
```

## 配置 example-app

这是一个示例的程序，程序通过 web (8080) 端口暴漏 metrics 监控指标。

```
cat <<EOF> example-app.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: example-app
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: example-app
    spec:
      containers:
      - name: example-app
        image: fabxc/instrumented_app
        ports:
        - name: web
          containerPort: 8080
---
kind: Service
apiVersion: v1
metadata:
  name: example-app
  labels:
    app: example-app
spec:
  selector:
    app: example-app
  ports:
  - name: web
    port: 8080
EOF
kubectl apply -f example-app.yaml
```

## 配置 ServiceMonitor

servicemonitor 通过 `matchLabels` 跟 service 进行关联。

```
cat <<EOF> servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: example-app
  labels:
    team: frontend
spec:
  selector:
    matchLabels:
      app: example-app
  endpoints:
  - port: web
EOF
kubectl apply -f servicemonitor.yaml
```

## 创建 prometheus

prometheus 通过 `serviceMonitorSelector` 搜集 ServiceMonitor 暴漏的监控指标。通过 `ruleSelector` 来进行报警规则的匹配，将规则以配置文件的形式加入到 prometheus 中。通过 nodeport `30900`进行访问

```
cat <<EOF> prometheus.yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources:
  - configmaps
  verbs: ["get"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: default
---
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: example
spec:
  serviceAccountName: prometheus
  replicas: 2
  alerting:
    alertmanagers:
    - namespace: default
      name: alertmanager-example
      port: web
  serviceMonitorSelector:
    matchLabels:
      team: frontend
  ruleSelector:
    matchLabels:
      role: alert-rules
      prometheus: example
  resources:
    requests:
      memory: 400Mi
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  type: NodePort
  ports:
  - name: web
    nodePort: 30900
    port: 9090
    protocol: TCP
    targetPort: web
  selector:
    prometheus: example
EOF
kubectl apply -f prometheus.yml
```

## 配置 alertmanager

创建 `secret`，将 Alertmanager 配置保存为 alertmanager.yaml，这个 secret 会载入到 alertmanager 实例中。

```
cat <<EOF> alertmanager.yaml
global:
  resolve_timeout: 5m
route:
  group_by: ['job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'webhook'
receivers:
- name: 'webhook'
  webhook_configs:
  - url: 'http://alertmanagerwh:30500/'
EOF

kubectl create secret generic alertmanager-example --from-file=alertmanager.yaml
```

创建 alertmanager, 定义了一个 3 pod 的 altermanager 集群，通过 `name` 字段生成的 pod 为 `alertmanager-example-0` 通过 `PrometheusRule` 会为 prometheus 的 rules 中生成相应的规则

```
cat <<EOF> alertmanager-example.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-example
spec:
  type: NodePort
  ports:
  - name: web
    nodePort: 30903
    port: 9093
    protocol: TCP
    targetPort: web
  selector:
    alertmanager: example
---
apiVersion: monitoring.coreos.com/v1
kind: Alertmanager
metadata:
  name: example
spec:
  replicas: 3
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  creationTimestamp: null
  labels:
    prometheus: example
    role: alert-rules
  name: prometheus-example-rules
spec:
  groups:
  - name: ./example.rules
    rules:
    - alert: ExampleAlert
      expr: vector(1)
EOF
kubectl apply -f alertmanager-example.yaml
```


## 配置 kube-prometheus

kube-prometheus 是通过 prometheus-operator 将 kubernetes 集群的指标搜集到 prometheus 中.

```
git clone https://github.com/coreos/prometheus-operator.git
cd prometheus-operator
sed -ri 's@quay.io/(.*)/@kuopsquay/\1.@g' contrib/kube-prometheus/manifests/*
kubectl  apply -f contrib/kube-prometheus/manifests
```
