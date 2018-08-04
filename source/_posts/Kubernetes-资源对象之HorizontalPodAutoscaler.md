---
title: Kubernetes 资源对象之 HorizontalPodAutoscaler
date: 2018-08-04 22:02:02
categories:
- kubernetes
---

## Horizontal Pod Autoscaler

简称 hpa ，kubernetes 能够根据监测到的 CPU 利用率（或者通过自定义的指标）自动的扩缩容 replication controller，deployment 和 replica set 中 pod 的数量，hpa 不适用于 daemonset。

Horizontal Pod Autoscaler 由一个控制循环实现，循环周期由 controller manager 中的 `--horizontal-pod-autoscaler-sync-period` 标志指定（默认是 30 秒）。


在每个周期内，controller manager 会查询 HorizontalPodAutoscaler 中定义的 metric 的资源利用率。Controller manager 从 resource metric API（每个 pod 的 resource metric）或者自定义 metric API（所有的metric）中获取 metric。

HPA 通过一系列的 metrics API 获取指标。使用 HPA 时必须启用 `API aggregation layer` ，

- `metrics.k8s.io` ，通过 `metrics-server` 提供标准指标

- `custom.metrics.k8s.io` 通过 `rometheus Adapter` 和 `Google Stackdriver (coming soon)` 提供自定义指标

- `external.metrics.k8s.io` 通过自定义指标的适配器启动。



## 配置 metric-server

必须先配置 aggregation layer, 在 kube-apiserver 启动以下参数:

```
--requestheader-client-ca-file=<path to aggregator CA cert>
--requestheader-allowed-names=aggregator
--requestheader-extra-headers-prefix=X-Remote-Extra-
--requestheader-group-headers=X-Remote-Group
--requestheader-username-headers=X-Remote-User
--proxy-client-cert-file=<path to aggregator proxy cert>
--proxy-client-key-file=<path to aggregator proxy key>
```

如果你的 apiserver 所在节点没有安装 kube-proxy ，则需要使用以下参数

```
--enable-aggregator-routing=true
```

metric-server 通过 kubelet 的 readOnlyPort 搜集节点数据，所以要在 kubelet 节点启动此端口

```
readOnlyPort: 10255
```

从 kubernets 1.11 开始 heapster 将被弃用，通过 metric-server 替换, 启动 metric-server

```
git clone https://github.com/kubernetes-incubator/metrics-server.git
kubectl create -f deploy/1.8+/
```

当 metric-server 启动之后，可以使用 `kubectl top` 查看

```
[root@k8s-master1 php]# kubectl  top node
NAME          CPU(cores)   CPU%      MEMORY(bytes)   MEMORY%   
k8s-master1   162m         8%        1327Mi          69%       
k8s-master2   144m         7%        1306Mi          68%       
k8s-master3   186m         9%        1514Mi          79%       
k8s-node1     79m          3%        1604Mi          10%       
[root@k8s-master1 php]# kubectl  top pod
NAME        CPU(cores)   MEMORY(bytes)   
ceph-pod1   0m           3Mi    
```

## HPA 示例

为了演示 Horizontal Pod Autoscaler，我们将使用基于 php-apache 图像的自定义 docker 镜像。Dockerfile 具有以下内容：

```
FROM php:5-apache
ADD index.php /var/www/html/index.php
RUN chmod a+rx index.php
```

它定义了一个 index.php 页面，它执行一些CPU密集型计算：

```
<?php
  $x = 0.0001;
  for ($i = 0; $i <= 1000000; $i++) {
    $x += sqrt($x);
  }
  echo "OK!";
?>
```

首先，我们将启动运行映像的部署并将其作为服务公开：

```
kubectl run php-apache --image=kuops/hpa-example --requests=cpu=200m --expose --port=80
```

### 创建 hpa

hpa 会通过增加或减少 pod 的数量使其始终保持在 50%，最小为 1 个，最大为 10 个，由于每个 Pod 通过 `kubectl run` 申请了200 milli-cores CPU，所以50%的CPU利用率意味着平均CPU利用率为100 milli-cores）

```
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10
```

查看 hpa 状态

```
[root@k8s-master1 ~]# kubectl get hpa
NAME         REFERENCE               TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache   0%/50%    1         10        1          2m
```

### 增加负载

```
kubectl run -i --tty load-generator --image=busybox /bin/sh

while true; do wget -q -O- http://php-apache.default.svc.cluster.local; done
```

过几分钟后，通过另一个终端查看,负载已经升高了

```
[root@k8s-master1 ~]# kubectl get hpa
NAME         REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache   485%/50%   1         10        1          6m
```

在我们的环境中，由于请求增多，CPU利用率已经升至 485%。 因此，Deployment的副本数量已经增长到了 4

```
[root@k8s-master1 ~]# kubectl get deployments php-apache 
NAME         DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
php-apache   4         4         4            4           1h
```

### 停止负载

在 busybox 中输入 `<Ctrl> + C` 来终止负载的产生，当 cpu 使用率下降时，系统也已经到缩减到了  1个 pod
```
[root@k8s-master1 ~]# kubectl get hpa
NAME         REFERENCE               TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache   0%/50%    1         10        4          11m
[root@k8s-master1 ~]# kubectl get deployments php-apache 
NAME         DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
php-apache   1         1         1            1           1h
```

> 注意：自动缩放副本可能需要几分钟。


### 指定 hpa 通过 cpu 和 memory

利用`autoscaling/v2alpha1`API版本（API version），您可以在自动伸缩`php-apache`这个Deployment时引入其他度量指标, 这里示例使用 metrics-server 的标准指标。

查看 api 是否支持 `autoscaling/v2alpha1` 版本

```
kubectl api-versions |grep 'autoscaling/v2beta1'
```

查看 api 对应的服务名称

```
[root@k8s-master1 ~]# kubectl get apiservices.apiregistration.k8s.io |grep 'metrics.k8s.io'
v1beta1.metrics.k8s.io                 2018-07-28T00:44:57Z
```

通过 raw 访问 metric api
```
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes/<node-name>
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespace/<namespace-name>/pods
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespace/<namespace-name>/pods/<pod-name>
```

访问 metrics-server 搜集的 php-apache pod 的 metrics

```
[root@k8s-master1 ~]# kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/default/pods |jq
{
  "kind": "PodMetricsList",
  "apiVersion": "metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/metrics.k8s.io/v1beta1/namespaces/default/pods"
  },
  "items": [
    {
      "metadata": {
        "name": "php-apache-666fb5c88c-dl52l",
        "namespace": "default",
        "selfLink": "/apis/metrics.k8s.io/v1beta1/namespaces/default/pods/php-apache-666fb5c88c-dl52l",
        "creationTimestamp": "2018-08-04T05:46:05Z"
      },
      "timestamp": "2018-08-04T05:46:00Z",
      "window": "1m0s",
      "containers": [
        {
          "name": "php-apache",
          "usage": {
            "cpu": "0",
            "memory": "11280Ki"
          }
        }
      ]
    }
  ]
}
```

指定 hpa 通过 cpu 和 memory：

```
cat <<EOF> hpa-php-apache.yaml
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1beta1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 50
  - type: Resource
    resource:
      name: memory
      targetAverageValue: 20Mi
EOF

kubectl apply -f hpa-php-apache.yaml
```

再次查看 hpa

```
[root@k8s-master1 ~]# kubectl get hpa
NAME         REFERENCE               TARGETS                  MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache   11550720/200Mi, 0%/50%   1         10        1          5d

[root@k8s-master1 ~]# kubectl get hpa.v2beta1.autoscaling  -o yaml
...
    metrics:
    - resource:
        name: memory
        targetAverageValue: 200Mi
      type: Resource
    - resource:
        name: cpu
        targetAverageUtilization: 50
      type: Resource
    minReplicas: 1
    scaleTargetRef:
      apiVersion: apps/v1beta1
      kind: Deployment
      name: php-apache
...
```

### 通过 promethus 自定义指标 hpa

创建 promethus ，`make certs` 需要安装 go 和 cfssl，安装方法自行搜索

```
git clone https://github.com/stefanprodan/k8s-prom-hpa.git
kubectl apply  -f ./namespaces.yaml
kubectl apply  -f ./prometheus
make certs
kubectl apply -f ./custom-metrics-api
```

查看 api 版本
```
[root@k8s-master1 k8s-prom-hpa]# kubectl api-versions |grep 'custom.metrics.k8s.io'
custom.metrics.k8s.io/v1beta1
```

列出 promethus 的自定义指标

```
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq
```

列出 promemthus 的 pod 自定义指标

```
[root@k8s-master1 k8s-prom-hpa]# kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .  |grep "pods/"
      "name": "pods/spec_cpu_period",
      "name": "pods/cpu_usage",
      "name": "pods/fs_io_time",
      "name": "pods/memory_usage_bytes",
      "name": "pods/fs_limit_bytes",
      "name": "pods/fs_reads_bytes",
      "name": "pods/fs_sector_writes",
      "name": "pods/memory_rss",
      "name": "pods/network_udp_usage",
      "name": "pods/cpu_schedstat_run_periods",
      "name": "pods/cpu_user",
      "name": "pods/fs_io_time_weighted",
      "name": "pods/spec_cpu_shares",
      "name": "pods/fs_sector_reads",
      "name": "pods/fs_usage_bytes",
      "name": "pods/memory_failcnt",
      "name": "pods/network_tcp_usage",
      "name": "pods/spec_memory_reservation_limit_bytes",
      "name": "pods/cpu_system",
      "name": "pods/fs_inodes_free",
      "name": "pods/fs_inodes",
      "name": "pods/spec_memory_swap_limit_bytes",
      "name": "pods/start_time_seconds",
      "name": "pods/tasks_state",
      "name": "pods/memory_working_set_bytes",
      "name": "pods/cpu_load_average_10s",
      "name": "pods/fs_write",
      "name": "pods/memory_failures",
      "name": "pods/cpu_cfs_throttled",
      "name": "pods/cpu_schedstat_runqueue",
      "name": "pods/fs_writes",
      "name": "pods/fs_io_current",
      "name": "pods/fs_reads",
      "name": "pods/cpu_cfs_periods",
      "name": "pods/cpu_cfs_throttled_periods",
      "name": "pods/cpu_schedstat_run",
      "name": "pods/memory_swap",
      "name": "pods/fs_reads_merged",
      "name": "pods/fs_writes_bytes",
      "name": "pods/memory_cache",
      "name": "pods/memory_max_usage_bytes",
      "name": "pods/spec_cpu_quota",
      "name": "pods/spec_memory_limit_bytes",
      "name": "pods/fs_read",
      "name": "pods/fs_writes_merged",
      "name": "pods/last_seen",
```

查看 monitoring 命名空间中所有 pod 的 FS usage ：

```
[root@k8s-master1 k8s-prom-hpa]# kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/monitoring/pods/*/fs_usage_bytes" | jq .
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta1/namespaces/monitoring/pods/%2A/fs_usage_bytes"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "monitoring",
        "name": "custom-metrics-apiserver-77fbff9cd8-vm8j8",
        "apiVersion": "/__internal"
      },
      "metricName": "fs_usage_bytes",
      "timestamp": "2018-08-04T09:52:37Z",
      "value": "133537792"
    },
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "monitoring",
        "name": "prometheus-7d4f6d4454-bb5g8",
        "apiVersion": "/__internal"
      },
      "metricName": "fs_usage_bytes",
      "timestamp": "2018-08-04T09:52:37Z",
      "value": "16384"
    }
  ]
}
```
创建一个 测试的 pod 和 service
```
kubectl create -f ./podinfo/podinfo-svc.yaml,./podinfo/podinfo-dep.yaml
```
该 `podinfo` 应用程序公开自定义指标 `http_requests_total` 。Prometheus 适配器删除 `_total` 后缀并将度量标记为计数器度量标准。

从自定义指标API获取每秒的总请求数：

```
[root@k8s-master1 k8s-prom-hpa]# kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests" | jq .
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/%2A/http_requests"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "podinfo-7b68779d-4kppx",
        "apiVersion": "/__internal"
      },
      "metricName": "http_requests",
      "timestamp": "2018-08-04T10:20:44Z",
      "value": "222m"
    },
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "podinfo-7b68779d-nwjc4",
        "apiVersion": "/__internal"
      },
      "metricName": "http_requests",
      "timestamp": "2018-08-04T10:20:44Z",
      "value": "219m"
    }
  ]
}
```

`m` 表示 `milli-units` , 示例里面的 `222m` 表示 222 个 `milli-units`。

创建 hpa ，podinfo如果请求数超过每秒10个，将增加 pod ：
```
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: podinfo
spec:
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: podinfo
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Pods
    pods:
      metricName: http_requests
      targetAverageValue: 10

kubectl create -f ./podinfo/podinfo-hpa-custom.yaml
```

几秒钟后，HPA 从指标 http_requests 获取值：
```
[root@k8s-master1 k8s-prom-hpa]# kubectl get hpa podinfo 
NAME      REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
podinfo   Deployment/podinfo   898m/10   2         10        2          1m
```

进行压力测试,每秒 25 个请求
```
go get -u github.com/rakyll/hey
PODINFO_IP=$(kubectl get svc podinfo -o jsonpath={.spec.clusterIP})
PODINFO_PORT=$(kubectl get svc podinfo -o jsonpath={.spec.ports[].port})
~/go/bin/hey -n 10000 -q 5 -c 5 http://${PODINFO_IP}:${PODINFO_PORT}/healthz
```

查看 events 信息，由于 3 个 pod 足以处理 25 个请求，所以 pod 不会在增加

```
[root@k8s-master1 ~]# kubectl get hpa podinfo 
NAME      REFERENCE            TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
podinfo   Deployment/podinfo   8318m/10   2         10        3          1h

[root@k8s-master1 ~]# kubectl describe hpa podinfo 
...
Events:
  Type    Reason             Age   From                       Message
  ----    ------             ----  ----                       -------
  Normal  SuccessfulRescale  9s    horizontal-pod-autoscaler  New size: 3; reason: pods metric http_requests above target
```

当负载完成时， pod 又会恢复到初始的的两个

```
Events:
  Type    Reason             Age        From                       Message
  ----    ------             ----       ----                       -------
  Normal  SuccessfulRescale  6m         horizontal-pod-autoscaler  New size: 3; reason: pods metric http_requests above target
  Normal  SuccessfulRescale  <invalid>  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```
