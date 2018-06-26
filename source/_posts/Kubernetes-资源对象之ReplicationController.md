---
title: Kubernetes-资源对象之ReplicationController
date: 2018-06-26 09:01:20
categories:
- kubernetes
---

## ReplicationController

ReplicationController 是 Pod 控制器的一种，一般而言，Pod 不会去直接定义，而是通过控制器去创建，可以帮助控制 Pod 总是以期望的结果运行。与手动创建的 pod 不同，由 ReplicationController 维护的 pod 在失败，被删除或终止时会自动替换。

例如，在进行破坏性维护（例如内核升级）之后，您的 Pod 将在节点上重新创建。因此，即使您的应用程序只需要一个 Pod，也应该使用 ReplicationController。ReplicationController 类似于进程管理器，但不是监督单个节点上的单个进程，而是通过 ReplicationController 监控多个节点上的多个进程。

在平常谈论中，ReplicationController 通常缩写为 `rc` 或 `rcs` ，并且作为 kubectl 命令的快捷方式。

一个简单的例子是创建一个 ReplicationController 对象，以无限期可靠地运行 Pod 的一个实例。更复杂的用例是运行复制服务的多个相同副本，例如 Web 服务器。



## 编写 ReplicationController Spec

与其他 Kubernetes 配置一样，ReplicationController 需要 `apiVersion`、 `kind` 和 `metadata` 字段，不同的是 ReplicationController 还需要一个 `.spec` 部分。

### Pod Template

这 `.spec.template` 是 `.spec` 中的必须字段，`.spec.template` 是一个pod模板。它与pod的样式完全相同，除了它是嵌套的，并且没有 apiVersion 和 kind。除了 Pod 的必需字段外，ReplicationController 中的pod 模板还必须指定适当的标签和适当的重新启动策略。对于标签，请确保不要与其他控制器重叠。

`.spec.template.spec.restartPolicy` 只允许等于 `Always`，如果未指定，则为默认值。

对于本地容器重新启动，ReplicationController委托给节点上的代理，例如 Kubelet 或 Docker 。


### Label

ReplicationController 本身可以有标签 (`.metadata.labels`）。通常情况下，你可以将它们设置为相同的 `.spec.template.metadata.labels`; 如果 `.metadata.labels` 未指定，则默认为 `.spec.template.metadata.labels`。但是，它们可以不同，并且 `.metadata.labels`不会影响ReplicationController 的行为。


### Pod Selector

`.spec.selector` 字段是一个标签选择器。ReplicationController 管理所有标签与选择器匹配的 Pod 。它不区分pod是某人或某个进程创建或删除的。这允许更换 ReplicationController 而不影响正在运行的 pod。


如果指定 `selector`，`.spec.template.metadata.labels` 必须与 `.spec.selector` 相同，否则将被API拒绝。如果 `.spec.selector` 未指定，则将默认为 `.spec.template.metadata.labels`。

另外，您不能直接通过另一个 ReplicationController 或另一个类似于 Job 的 controller 来创建与这个 labels 相同 selector 的 pod。 否则， ReplicationController 会认为这些 pod 是由它创建的。Kubernetes 不会阻止你这样做。

如果最终使用具有相同 selector 的多个 controller ，则必须自己去删除。

### Replicas

您可以设置 `.spec.replicas` 来指定您想要同时运行的 pod 数量。有时候运行的数量可能会更高或更低，例如副本刚刚增加或减少，或者如果一个容器正常关机，并且提前开始更换。

如果您没有指定`.spec.replicas`的数量, 默认值是1


## 使用 ReplicationController

### 创建 Pod

这是一个 ReplicationController 配置示例。它运行3个 nginx Web 服务副本。

```
cat <<EOF> replication.yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    app: nginx
  template:
    metadata:
      name: nginx
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF
kubectl create -f replication.yaml
```
查看 replicationcontroller 状态
```
[root@kubernetes ~]# kubectl describe replicationcontroller nginx
...
  Normal  SuccessfulCreate  4m    replication-controller  Created pod: nginx-4tdl7
  Normal  SuccessfulCreate  4m    replication-controller  Created pod: nginx-qrpdw
  Normal  SuccessfulCreate  4m    replication-controller  Created pod: nginx-9wcf2
```

可以使用如下命令列出属于 rc 的所有 pod ：
```
kubectl get pods --selector=app=nginx --output=jsonpath={.items..metadata.name}
```

### 删除 ReplicationController 和 Pod

使用以下命令删除 ReplicationController nginx  及其它的所有 pod，在删除 ReplicationController 本身之前， Kubectl 会将 ReplicationController 缩容为零并等待它删除完 pod 。 如果 kubectl 命令被中断，它会被重启。

>注意:当使用 REST API 或 go 客户端库时，您需要明确地执行这些步骤（将 replicas 缩容为 0，等待 pod 删除，然后删除 ReplicationController ）。

```
kubectl  delete  replicationcontroller nginx
```

### 只删除 ReplicationController

使用 kubectl ，为 `kubectl delete`指定 `--cascade=false` 选项。
使用 REST API 或go 客户端库时，只需删除 ReplicationController 对象即可。
当原始的 ReplicationController 被删除后，您可以创建一个新的 ReplicationController 来替换它。 只要旧的和新的 `.spec.selector` 是一样的，那么新的 ReplicationController 将会接管旧的 pod 。 但是，在不同 pod template 的情况下，现有的 pod 是不会去匹配新的 template 。 使用 `rolling update` 以可控的方式将 pod 更新为新的 spec 。
```
kubectl  delete --cascade=false replicationcontroller nginx
```

### 重新调度

无论您是要运行1个 pod 还是1000个， ReplicationController 将保持指定数量的 pod 存在，即使在节点故障或 pod 终止的情况下（例如，由于其他控制代理的操作）。

### 扩容与缩容

通过简单地更新 replicas 字段， ReplicationController 可以自动扩容和缩容 replica 的数量。
```
kubectl scale --replicas=1 rc/nginx
```

### 滚动更新

滚动升级在客户端工具中实现 `kubectl rolling-update`。

### 多版本跟踪

例如，一个 service 可能会以 标签 `tier in (frontend), environment in (prod)` 指向所有的 pod 。加入你有10个 pod 的 replicas 组成了这一层。创建一个新的 `canary` 版本。您可以设置一个 ReplicationController ，replicas对于带有标签 `tier=frontend, environment=prod, track=stable`设置为9, 另一个 ReplicationController 的  replicas设置为 1 ，带有标签为 `tier=frontend, environment=prod, track=canary`。现在该 service 包括了金丝雀和非金丝雀 pod 。但是你可以单独使用ReplicationController来测试，监控结果等。


### 使用 ReplicationControllers 与 Services

一个 service 可以对应多个 ReplicationControllers ，比如，一些流量转到旧版本，一些转到新版本。

ReplicationController 永远不会自动终止，但不会像 service 一样长期存在。 service 可能由多个 ReplicationControllers 控制的 pod 组成，并且可能会在 service 的整个生命周期内可能会创建和销毁许多 ReplicationControllers （例如，执行运行该服务的 pod 的更新）。 不管是服务本身还是其客户端都应该为 ReplicationControllers 保留维护服务的pod。

## replication 的替代品

### ReplicaSet
`ReplicaSet` 是支持新的基于集合的标签选择器的下一代 ReplicationController 。它主要被 `Deployment` 用作协调 pod 创建，删除和更新的机制。请注意，我们建议您使用 `deployment` 而不是直接使用 `replicaset`，除非您需要自定义更新业务流程或根本不需要更新。


### Deployment（推荐）
`Deployment` 是一个更高级别的 API 对象，它更新 Pod 类似于 `ReplicaSet` 的 `kubectl rolling-update`方式。 如果您想要这种滚动更新功能，建议使用 `Deployments` ，因为与 `kubectl rolling-update` 不同，它是声明式的、服务器端的，并且还具有其他功能。

### Job
使用 `Job` 代替 ReplicationController ，用于自己预计终止的 pod （即批处理作业）。

### DaemonSet

使用 `DaemonSet` 代替 ReplicationController 来提供机器级功能，例如机器监控或机器日志记录。 这些 pod 的生命周期与机器生命周期绑在一起：这些 pod 会在其他 pod 启动之前启动，并且当机器准备重新启动/关闭时会安全的终止。






