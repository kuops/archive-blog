---
title: 创建 Kubernetes 集群：配置 EFK
date: 2018-07-19 13:31:40
tags:
categories:
- kubernetes
---

> 本片文章为创建 Kubernets 集群 `第十五部分`
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

## Elasticsearch

我们通过 GitHub 存储库 https://github.com/pires/kubernetes-elasticsearch-cluster.git 来进行配置

创建 ES 集群, 默认的 JMX 是 256m ，可以适当调大。

```
git clone https://github.com/pires/kubernetes-elasticsearch-cluster.git
cd kubernetes-elasticsearch-cluster
sed -ri 's@quay.io/(.*)/@kuopsquay/\1.@' *.yaml
sed -ri 's@docker.elastic.co/kibana/@kuopsme/kibana.@gp' *.yaml

kubectl create ns logging
kubectl create -n logging -f es-discovery-svc.yaml
kubectl create -n logging -f es-svc.yaml
kubectl create -n logging -f es-master.yaml
kubectl rollout status -n logging -f es-master.yaml

kubectl create -n logging -f es-ingest-svc.yaml
kubectl create -n logging -f es-ingest.yaml
kubectl rollout status -n logging -f es-ingest.yaml

kubectl create -n logging -f es-data.yaml
kubectl rollout status -n logging -f es-data.yaml
```

测试 es 运行情况

```
[root@k8s-master1 kubernetes-elasticsearch-cluster]# kubectl -n logging get pod -l component=elasticsearch
NAME                         READY     STATUS    RESTARTS   AGE
es-data-76969c65-88xdp       1/1       Running   1          9m
es-data-76969c65-kmvv2       1/1       Running   3          9m
es-ingest-65765b47cc-62wx5   1/1       Running   0          4m
es-ingest-65765b47cc-w6lkm   1/1       Running   0          4m
es-master-6b4d94fcf8-2m7r2   1/1       Running   3          9m
es-master-6b4d94fcf8-5wht6   1/1       Running   4          9m
es-master-6b4d94fcf8-lfxp4   1/1       Running   3          9m
[root@k8s-master1 kubernetes-elasticsearch-cluster]# kubectl -n logging get svc -l component=elasticsearch
NAME                      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
elasticsearch             ClusterIP   10.96.1.82     <none>        9200/TCP   18m
elasticsearch-discovery   ClusterIP   None           <none>        9300/TCP   18m
elasticsearch-ingest      ClusterIP   10.96.58.224   <none>        9200/TCP   18m

[root@k8s-master1 kubernetes-elasticsearch-cluster]# curl 10.96.1.82:9200
{
  "name" : "es-data-76969c65-kmvv2",
  "cluster_name" : "myesdb",
  "cluster_uuid" : "TYluO0rdTnWamr5TwY320A",
  "version" : {
    "number" : "6.3.0",
    "build_flavor" : "default",
    "build_type" : "tar",
    "build_hash" : "424e937",
    "build_date" : "2018-06-11T23:38:03.357887Z",
    "build_snapshot" : false,
    "lucene_version" : "7.3.1",
    "minimum_wire_compatibility_version" : "5.6.0",
    "minimum_index_compatibility_version" : "5.0.0"
  },
  "tagline" : "You Know, for Search"
}

[root@k8s-master1 kubernetes-elasticsearch-cluster]# curl 10.96.1.82:9200/_cluster/health?pretty
{
  "cluster_name" : "myesdb",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 7,
  "number_of_data_nodes" : 2,
  "active_primary_shards" : 0,
  "active_shards" : 0,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0,
  "delayed_unassigned_shards" : 0,
  "number_of_pending_tasks" : 0,
  "number_of_in_flight_fetch" : 0,
  "task_max_waiting_in_queue_millis" : 0,
  "active_shards_percent_as_number" : 100.0
}
```

## fluent bit

使用 `fluent bit` 对日志进行搜集
```
kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml
kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml
kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role-binding.yaml
```

创建自定义的 config 配置文件
```
kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-configmap.yaml
```

创建完成之后，通过 daemonset 启动 fluent bit

```
cat <<EOF> fluent-bit-ds.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
  labels:
    component: fluent-bit-logging
    version: v1
    kubernetes.io/cluster-service: "true"
spec:
  selector:
    matchLabels:
      component: fluent-bit-logging
  template:
    metadata:
      labels:
        component: fluent-bit-logging
        version: v1
        kubernetes.io/cluster-service: "true"
    spec:
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:0.13.5
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: "elasticsearch" # the name of the previous es-svc.yml 
        - name: FLUENT_ELASTICSEARCH_PORT
          value: "9200" # the port of the previous es-svc.yml 
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc/
      terminationGracePeriodSeconds: 10
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config # name of the previously created ConfigMap
      serviceAccountName: fluent-bit
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
EOF
kubectl apply -f  fluent-bit-ds.yaml
```

## kibana

使用 Kibana 可视化部署。

```
cat <<EOF> kibana.yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  namespace: logging
  name: kibana
  labels:
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
     component: kibana
  template:
    metadata:
      labels:
        component: kibana
    spec:
      containers:
      - name: kibana
        image: kuopsme/kibana.kibana-oss:6.3.0
        env:
        - name: CLUSTER_NAME
          value: myesdb
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        ports:
        - containerPort: 5601
          name: http
---
apiVersion: v1
kind: Service
metadata:
  namespace: logging
  name: kibana
  labels:
    component: kibana
spec:
  selector:
    component: kibana
  ports:
  - name: http
    port: 5601
EOF
kubectl apply -f  kibana.yaml
```

配置 ingress ：

```
cat <<EOF> kibana-ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: kibana
  namespace: logging
  annotations:
    kubernetes.io/ingress.class: traefik
    ingress.kubernetes.io/auth-type: "basic"
    ingress.kubernetes.io/auth-secret: kibana-basic-auth
spec:
  rules:
  - host: kibana.k8s.kuops.com
    http:
      paths:
      - backend:
          serviceName: kibana
          servicePort: http
        path: /
EOF
kubectl apply -f kibana-ingress.yaml
```

创建 traefik 的 http 基本认证 secret ：

```
htpasswd -c ./auth <your-user>
kubectl -n logging create secret generic kibana-basic-auth --from-file auth
```

现在可以通过 ingress 当问 Kibana ，添加索引 `logstash-*` 。
