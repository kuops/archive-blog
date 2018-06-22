---
title: Kubernetes 资源对象之ConfigMap
date: 2018-06-22 23:02:02
categories:
- kubernetes
---

## ConfigMap

编写应用程序时的一个好习惯是将应用程序代码与配置文件分开。我们希望使应用程序的作者能够在 Kubernetes 中轻松使用这种模式。虽然 `Secrets API` 允许从应用程序中分离信息（如凭证和密钥），但过去不存在用于普通，非秘密配置的对象。在 `Kubernetes 1.2` 中，添加了一个名为 `ConfigMap` 的新 API 资源来处理这种类型的配置数据。

`ConfigMap API` 在概念上很简单。从数据的角度来看，ConfigMap 类型只是一组键值对。应用程序以不同的方式进行配置，因此我们需要灵活地了解我们如何让用户存储和使用配置数据。有三种方法可以在 pod 中使用 ConfigMap：

- 设置容器启动命令的启动参数
- 生成为容器内的环境变量。
- 以Volume形式挂载为容器内部的文件或目录

这些不同的方法适用于对正在使用的数据进行建模的不同方式。为了尽可能灵活，我们使 ConfigMap 保存了精细和/或粗粒度的数据。此外，因为应用程序从环境变量和包含配置数据的文件读取配置设置，所以我们构建 ConfigMap 以支持任一种访问方法。

## 使用 ConfigMap 的限制条件

- ConfigMap 必须在 Pod 之前创建；

- ConfigMap 受到 NameSpace 限制， 只有处于相同的 NameSpace中的Pod才可以引用；

- ConfigMap 中的配额管理还未能实现。

- kubelet 只支持可以被 Api Server 管理的 Pod 使用 ConfigMap。

- 在 Pod 对 ConfigMap 挂载时， 容器内部只能挂载为目录， 无法挂载为文件。在挂载到容器内部后，目录将包含 ConfigMap 的每个 item ，如果目录下原来还有其他文件，将会被覆盖。如果应用程序需要保留原来的其他文件， 则需要进行额外的处理。可以将 ConfigMap 挂载到容器内的临时目录，再通过启动脚本 （cp 或 link命令）应用到实际的配置目录下。

- 如果使用 `envFrom` 获取 ConfigMap 定义得环境变量，无效的 Key 会被忽略。Pod可以启动，但是无效的名字将会被记录在事件日志里(InvalidVariableNames). 日志消息会列出来每个被忽略的 Key ，比如：
```
   kubectl get events
   LASTSEEN FIRSTSEEN COUNT NAME          KIND  SUBOBJECT  TYPE      REASON                            SOURCE                MESSAGE
   0s       0s        1     dapi-test-pod Pod              Warning   InvalidEnvironmentVariableNames   {kubelet, 127.0.0.1}  Keys [1badkey, 2alsobad] from the EnvFrom configMap default/myconfig were skipped since they are considered invalid environment variable names
```

## ConfigMap 的格式

ConfigMap的data字段包含配置数据。如下例所示，这可以很简单 - 就像使用定义的单个属性一样 `--from-literal`，或者使用复杂的配置文件或JSON blob `--from-file` 。

```
kind: ConfigMap
apiVersion: v1
metadata:
  creationTimestamp: 2016-02-18T19:14:38Z
  name: example-config
  namespace: default
data:
  # example of a simple property defined using --from-literal
  example.property.1: hello
  example.property.2: world
  # example of a complex property defined using --from-file
  example.property.file: |-
    property.1=value-1
    property.2=value-2
    property.3=value-3
```


## 使用 ConfigMap 数据定义 Pod 环境变量

### 使用命令创建 configmap

在 ConfigMap 里将环境变量定义为键值对：

```
kubectl create configmap special-config --from-literal=special.how=very
```

将 ConfigMap 里的 `special.how` 值赋给 Pod 的环境变量 `SPECIAL_LEVEL_KEY`.

```
cat <<EOF> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: [ "/bin/sh", "-c", "env" ]
      env:
        # Define the environment variable
        - name: SPECIAL_LEVEL_KEY
          valueFrom:
            configMapKeyRef:
              # The ConfigMap containing the value you want to assign to SPECIAL_LEVEL_KEY
              name: special-config
              # Specify the key associated with the value
              key: special.how
  restartPolicy: Never
EOF
kubectl create -f dapi-test-pod.yaml
```
查看日志中的输出信息
```
[root@kubernetes ~]# kubectl   logs  dapi-test-pod |grep 'SPECIAL_LEVEL_KEY='
SPECIAL_LEVEL_KEY=very
```

### 使用 配置文件创建 configmap

使用来自多个 ConfigMaps 的数据定义 Pod 环境变量:

```
cat <<EOF> special-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: special-config
     namespace: default
   data:
     special.how: very
EOF

cat <<EOF> enc-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: env-config
     namespace: default
   data:
     log_level: INFO
EOF

kubectl create -f special-config.yaml
kubectl create -f enc-config.yaml
```
在 pod 中定义环境变量
```
cat <<EOF> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
  - name: test-container
    image: busybox
    command: [ "/bin/sh", "-c", "env" ]
    env:
      - name: SPECIAL_LEVEL_KEY
        valueFrom:
          configMapKeyRef:
            name: special-config
            key: special.how
      - name: LOG_LEVEL
        valueFrom:
          configMapKeyRef:
            name: env-config
            key: log_level
  restartPolicy: Never
EOF
kubectl create -f dapi-test-pod.yaml
```
查看变量
```
[root@kubernetes ~]# kubectl   logs   dapi-test-pod |grep -Pi 'log_level|special_level'
LOG_LEVEL=INFO
SPECIAL_LEVEL_KEY=very
```
### 将 ConfigMap 中的所有键值对配置为 Pod 环境变量

创建 configmap 和 pod 并输出变量
```
cat <<EOF> special-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: special-config
  namespace: default
data:
  SPECIAL_LEVEL: very
  SPECIAL_TYPE: charm
EOF
kubectl create -f special-config.yaml

cat <<EOF> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: [ "/bin/sh", "-c", "env" ]
      envFrom:
      - configMapRef:
          name: special-config
  restartPolicy: Never
EOF
kubectl create -f dapi-test-pod.yaml
```
查看变量
```
[root@kubernetes ~]# kubectl logs dapi-test-pod |grep -i 'SPE'
SPECIAL_LEVEL=very
SPECIAL_TYPE=charm
```

## 把 configmap 中的键值对作为容器的启动参数

configmap 还用上个例子的 configmap

```
cat <<'EOF'> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: [ "/bin/sh", "-c", "echo $(SPECIAL_LEVEL_KEY) $(SPECIAL_TYPE_KEY)" ]
      env:
        - name: SPECIAL_LEVEL_KEY
          valueFrom:
            configMapKeyRef:
              name: special-config
              key: SPECIAL_LEVEL
        - name: SPECIAL_TYPE_KEY
          valueFrom:
            configMapKeyRef:
              name: special-config
              key: SPECIAL_TYPE
  restartPolicy: Never
EOF
kubectl create -f dapi-test-pod.yaml
```
查看日志输出
```
[root@kubernetes ~]# kubectl   logs   dapi-test-pod
very charm
```

## 将 ConfigMap 数据添加到卷

在 Pod 的 volumes 下添加 ConfigMap 名称。这将 ConfigMap 数据添加到指定的目录 `volumeMounts.mountPath`（在本例中/etc/config）。

```
cat <<EOF> special-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: special-config
  namespace: default
data:
  special.level: very
  special.type: charm
EOF
kubectl create -f special-config.yaml

cat <<EOF> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: [ "/bin/sh", "-c", "ls /etc/config/" ]
      volumeMounts:
      - name: config-volume
        mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        # Provide the name of the ConfigMap containing the files you want
        # to add to the container
        name: special-config
  restartPolicy: Never
EOF
kubectl create -f dapi-test-pod.yaml
```
查看日志输出
```
[root@kubernetes ~]# kubectl logs dapi-test-pod
special.level
special.type
```
> 警告：如果/etc/config/目录中有一些文件，它们将被删除。

### 将 ConfigMap 数据添加到卷中的特定路径

```
cat <<EOF> dapi-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-test-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: [ "/bin/sh","-c","cat /etc/config/keys" ]
      volumeMounts:
      - name: config-volume
        mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        name: special-config
        items:
        - key: special.level
          path: keys
  restartPolicy: Never
EOF

kubectl create -f dapi-test-pod.yaml
```
查看日志输出
```
[root@kubernetes ~]# kubectl logs  dapi-test-pod
very
```

## 使用命令行创建 configmap

不使用 yaml 文件，直接通过 `kubectl create configmap` 也可以创建 ConfigMap， 可以使用参数 `--from-file` 或 `--from-literal` 指定内容， 并且可以在一行命令中指定多个参数。

1. 通过 --from-file 可以从文件创建，也可以指定 key 名称，也可以在一个命令中包含多个 key 的 ConfigMap ，语法为

```
kubectl create configmap NAME --from-file=[key=]source  --from-file=[key=]source 
```

2. 通过 --from-file 从目录中创建，该目录下的每个文件名都被设置为 key，文件内容被设置为 value ， 语法为：

```
kubectl create configmap NAME --from-file=config-files-dir
```

3.通过 --config-literal 从文本进行创建， 直接将指定的 key=value 创建为 ConfigMap 的内容：

```
kubectl create configmap NAME --from-literal=key1=value1 --from-literal=key2=value2
```

准备目录 configfiles 目录下包含两个文件 server.xml 和 logging.properties， 创建一个包含这两个文件的 ConfigMap：

```
kubectl  create configmap cm-appconf --from-file=configfiles
```

以单个文件创建

```
kubectl create configmap cm-server.xml --from-file=configfiles/server.xml
```

使用 --from-literal 参数进行创建：
```
kubectl  create configmap cm-appenv --from-literal=loglevel=info --from-literal=appdatadir=/var/data
```

从 env 文件创建 configmap ， 使用 `-from-env-file`
```
cat<<EOF> env.file
enemies=aliens
lives=3
allowed="true"
EOF
kubectl create configmap  env-file --from-env-file=env.file
```
查看数据
```
[root@kubernetes ~]# kubectl   get configmap env-file -o yaml
apiVersion: v1
data:
  allowed: '"true"'
  enemies: aliens
  lives: "3"
kind: ConfigMap
....
```


## ConfigMap 自动更新

当更新卷中已经使用的 ConfigMap 时，对应的 Key 也会被更新。Kubelet 会周期性的检查挂载的 ConfigMap 是否是最新的。 然而，它会使用本地基于 ttl 的 cache 来获取 ConfigMap 的当前内容。因此，从 ConfigMap 更新到 Pod 里的新 Key 更新这个时间，等于 Kubelet 的同步周期加 ConfigMap cache 的 ttl。


测试 configmap 自动更新
```
cat <<EOF> sync-configmap.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sync-configmap
  namespace: default
data:
  i: "1"
EOF

cat <<'EOF'> sync-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: sync-pod
spec:
  containers:
    - name: test-container
      image: busybox
      command: ["/bin/sh"]
      args: [ "-c","while true;do sleep 1 && echo $(date +%T) $(cat /etc/config/i);done" ]
      volumeMounts:
      - name: config-volume
        mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        name: sync-configmap
EOF
kubectl create -f sync-configmap.yml
kubectl create -f sync-pod.yaml

kubectl logs sync-pod


cat <<EOF> sync-configmap.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sync-configmap
  namespace: default
data:
  i: "2"
EOF
kubectl apply -f sync-configmap.yml

# 通过两段间隔可以看到更新周期差不多 40 多秒
kubectl logs -f sync-pod
```

