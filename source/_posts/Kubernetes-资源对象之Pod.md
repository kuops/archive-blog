---
title: Kubernetes-资源对象之Pod
date: 2018-06-12 06:02:02
categories:
- kubernetes
---

## Pod 简介

Pod 是 Kubernetes 可以创建和管理的最小单元。

一个 Pod 中包含一组容器（一个或多个），容器之间共享网络和存储。一个 Pod 中的容器之间是紧密相连的。一个 Pod 中的容器都会在相同的物理节点或者虚拟机上执行。

Kubernets 支持多种底层容器运行时环境，Docker 只是其中的一种实现。

## 多个 Pod 中的资源共享

多个 Pod 之间共享 Linux 的 Namaspace  和 cgroup 和其他底层的隔离设施，如果有紧耦合的服务，可以部署在一个 Pod 里。

**网络**
每个 Pod 被分配了唯一的 IP 地址。pod 里的所有容器共享着一个网络空间，这个网络空间包含了 IP 地址和网络端口。 Pod 内部的容器通过 `localhost` 进行通信。 但当 Pod 里的容器需要与外部通信时，共享同一 Pod 网络资源（IP 和 端口）。

**存储**
Pod 可以也可以指定共享的 Volume 。Pod 里所有的容器都由权限访问这个 Volume。当 Pod 重启时不会丢失 Volume 内的数据。


Pod 是一个一次性的，短生命周期的实例，在创建一个 Pod（直接被创建，或者是通过 Controller 间接创建）时，这个 pod 会被调用到集群里某一个节点上。 除非 Pod 进程被终止，或者 pod 对象被删除，或者由于缺少资源、节点失败等原因 pod 被驱逐，否则 Pod 将一直存在在这个节点上。

 pod 被创建后会分配一个唯一的 ID (UID),然后 pod 会被调度到一个节点上直到被终止（ 通过重启策略）或者被删除。如果一个节点停止运行， 其上的 pod 在一段时间后将被删除。 指定的 pod (由 UID 来标识)不会被重新调度到新节点上，而是会被另外一个等价 pod 取代。 这个 pod 名字可以与原来的相同，但是 UID 会重新生成。

pod 并不具备自我恢复的功能。如果 pod 被调度到一个宕机的节点，或者调度的操作本身就失败了，那么这个 pod 立刻会被删除；这个场景同样适用于缺少资源或者节点宕机的情况。Kubernetes 使用一个称作 Controller 高度抽象来管理相对可删除 pod。因此与单独直接使用一个 pod 相比，在 Kubernets 里更常见的情况是使用一个 Controller 来管理所有的 pod。



## Pod controller

一个 Controllers 可以创建和管理很多个 Pod, 也提供复制、初始化，以及提供集群范围的自我恢复的功能。比如说： 如果一个节点宕机，Controller 将调度一个在其他节点上完全相同的 pod 来自动取代当前的 pod。

下面这些是 Controllers 可以创建和管理多个 Pod ：

*   Deployment
*   StatefulSet
*   DaemonSet


## Pod 的使用

Pod也可以用于垂直应用栈（例如LAMP），这样使用的主要动机是为了支持共同调度和协调管理应用程序，比如说：

 * 内容管理系统， 文件和数据的导入，本地缓存管理等。
 * 日志和检查点的备份，压缩，轮转，快照等。
 * 数据变化监测，日志检测，日志和监控，事件发布等。
 * 代理， 桥接器, 和连接器。
 * 控制，管理，配置和更新管理。

通常每个 Pod 不应该运行同一应用的多个实例。


## Pod 复合容器使用示例

复合容器也就是一个 Pod 中运行多个容器实例。

### 例一： Sidecar 容器

![](/img/kubernetes-pod/pod-example-1.png)

Sidecar容器扩展并增强了主容器，它们将现有的容器变得更好。当你运行了一个 nginx 容器时，添加另一个容器，在两个容器之间共享文件系统，用来同步 git 代码，假如你这个 git 同步的容器已经模块化，可以复用在许多不同的Web服务器（Apache，Python，Tomcat等）由于这种模块化，您只需编写和测试一次git同步器，并在多个应用程序中重复使用它。

### 例二： 代理容器

![](/img/kubernetes-pod/pod-example-2.png)

代理容器代理 Pod 内部与外界的连接，当如果外部有一个读写分离的 redis 集群，可以创建一个代理容器，负责区分程序的读写，并把请求转发到的 redis 集群中。由于两个容器共享一个 IP 地址，所以在主程序中，不需要去关注 IP 地址，在应用程序中直接使用 localhost 连接，把关注点分离。

### 例三： 适配容器

![](/img/kubernetes-pod/pod-example-3.png)

适配器容器，使得输出标准化，考虑到监控不同的程序和任务，每个应用程序导出的监控数据都各不相同。但是每个监控系统都希望为其收集的监控数据提供一致且统一的数据模型。通过使用复合容器的适配模式，您可以通过创建 Pod 来将不同系统的监控数据，统一标准化。同样，因为这些 Pod 共享 namespace 和文件系统，所以这两个容器的协调很简单直接。


## 为什么不在一个容器里运行多个应用

**透明度：** 让 Pod 中的容器对基础设施可见，以便基础设施能够为这些容器提供服务，例如进程管理和资源监控。这可以为用户带来极大的便利。

**解耦软件依赖：** 每个容器都可以进行版本管理，独立的编译和发布。未来kubernetes甚至可能支持单个容器的在线升级。

**使用方便：** 用户不必运行自己的进程管理器，还要担心错误信号传播等。
**效率：**  基础架构提供更多的职责，所以容器可以变得更加轻量级。


## pods 持久性（pod 需要提升的方面）

Pod 从设计之出就不是为了持久化应用，一旦 调度失败，节点故障、资源不足、节点维护，都会结束 Pod 的生命周期。

Pod 通常不是直接创建的，而是通过 controller 进行创建的，Controller 提供了集群内部 Pod 自我修复、Pod 复制和回滚管理。像StatefulSet这样的控制器 也可以为有状态的pod提供支持。

使用集群 API 作为面向用户的主要原语言的方法在集群调度系统里很常见，包含了Borg, Marathon, Aurora, and Tupperware

Pod是作为一种原始语言暴露出来的，以便于：

- 调度程序和 controller 可插拔性
- 无需通过 controller API 代理即可支持 Pod 级操作
- Pod  生命周期与控制器生命周期的解耦
- controller  和服务的解耦，controller 的访问入口只是监控 pod
- 清楚的区分 kubelet 级别 和 cluster 级别的功能 - Kubelet实际上也是 `Pod controller`
- 高可用性应用程序，这些应用程序将期望在终止之前以及在删除之前（例如在计划驱逐或图像更新的情况下）来替换它们。


## Pods 的终止

由于 pods 代表群集中节点上的正在运行的进程，因此当不再需要这些进程时，允许这些进程正常终止（而不是通过发送KILL信号这种暴力的方式），这一点很重要。用户需要能够发起一个删除 Pod 的请求，知晓 Pod 何时终止，同时应该也能够确认这个删除事件是否已经完成。当用户提出删除一个 pod 的请求时，系统会记录预期的宽限期，然后允许 pod 被强制终止，并向每个容器的主进程发送一个 TERM 信号。一旦宽限期过期，KILL 信号将发送给这些进程，然后从 API server 中删除该容器。如果 Kubelet 或者 container manager 在等待进程终止的过程中重新启动，终止操作将在宽限期内反复重试。

示例流程：

1. 用户发送删除 Pod 的命令，默认宽限期（30s）

2. API server 中的 Pod 随着宽限期随着时间的推移而更新，Pod 被标记为 `dead`。

3. Pod 在客户端命令中列出时显示为 `Terminating`。

4. （与第3步同时发生）Kubelet 发现某一个 Pod 由于时间超过第 2 步的设置而被标志成 terminating 状态时， Kubelet 将启动一个停止进程。

    1. 如果 pod 已经被定义成一个 preStop hook，这会在 pod 内部进行调用。如果宽限期已经过期但 preStop hook 依然还在运行，将调用第 2 步并在原来的宽限期上加一个小的时间窗口（2 s）。

    2. 对 Pod 内部的进程发起 TERM 信号。

5. （与3同时）Pod 从 service 的 endpoints 列表中删除，不再被视为 replication controllers 的运行集的一部分。缓慢关闭的 Pod 可以继续为提供服务，因为负载均衡（如 service proxy）将它们从轮询中移除。

6. 当宽限期到期时，任何在 Pod 中运行的进程都将使用 SIGKILL 来终止。

7. Kubelet 将通过设置宽限期 0（立即删除）完成删除 API server 上的 Pod。Pod 从 API 中消失，客户端也不可见。

默认情况下，所有删除操作在 30 秒内。该 `kubectl delete` 命令支持 `--grace-period=<seconds>` 允许用户覆盖默认值并指定其自己的值的选项。值 `0` 强制删除 pod 。在 kubectl 版本在 1.5 或更高的版本，必须在使用 `--grace-period=0` 时指定一个额外的标志 `--force` 。


### 强制删除 pod

强制删除一个 pod 会从群集状态 和 etcd 中同时删除。当执行强制删除操作时，apiserver 不会等待 kubelet 确认该 pod 已在其运行的节点上终止。它会立即删除 API 中的 pod ，以便可以使用相同的名称创建新的 pod 。在节点上，将 pod 设置为立即终止时，在被强制杀死之前仍将被给予一个小的宽限期。

强制删除可能对某些Pod有潜在危险，应谨慎执行。对于 StatefulSet 生成的 pod ，请参阅从 StatefulSet 中 删除 pod 的文档。


## Pod 中使用特权模式

从 Kubernetes v1.1 开始， pod 的容器都可以启动特权模式，只需要将 container spec 的 SecurityContext 指定为 privileged 标志。这对于那些想使用网络栈操作以及访问系统设备等 Linux 能力的容器来说，是个非常有用的功能。 容器里的进程获得了与容器外进程几乎完全相同的权限。有了特权模式，编写网络和卷插件变得更加容易，因为它们可以作为独立的 Pod 运行，而无需编译到 kubelet 中去。

如果 master 运行的 Kubernetes 版本是 v1.1 或者更高，但是 node 上运行的版本低于 v1.1，api-server 虽然会接受新的特权 pod ，但这些 pod 却无法正常运行起来。 它们将一直处于 pending 状态。 当用户调用：

```
kubectl describe pod FooPodName
```

查看 pod 一直处于 pending 状态的原因时，在 describe command 的输出事件表里会有类似下面的信息：
```
Error validating pod "FooPodName"."FooPodNamespace" from api, ignoring: spec.containers[0].securityContext.privileged: forbidden '<*>(0xc2089d3248)true'
```

如果 master 运行的 Kubernetes 版本低于 v1.1，则不能创建特权Pod。在这种情况如果用户尝试去创建一个包含特权容器的 pod ，那么将会返回类似下面的错误信息：
```
The Pod "FooPodName" is invalid. spec.containers[0].securityContext.privileged: forbidden '<*>(0xc20b222db0)true'
```

## Pod 生命周期

### Pod 阶段
在 pod 生命周期中，有以下几个阶段：

*   待创建（Pending）：Pod 已被 Kubernetes 系统接受，但有一个或者多个容器镜像尚未创建。等待时间包括调度 Pod 的时间和通过网络下载镜像的时间，这可能需要花点时间。

*   运行中（Running）：Pod已绑定到节点，并且所有容器都已创建。至少有一个 Container 正在运行，或者正在启动或重新启动。

*   成功（Succeeded）：Pod 中的所有容器都被成功终止，并且不会再重启。

*   失败（Failed）：Pod 中的所有容器都已终止了，并且至少有一个容器是因为失败终止。也就是说，容器以非0状态退出或者被系统终止。

*   未知（Unknown）：出于某种原因，无法获得Pod的状态，通常是由于与Pod主机通信时出错。

### Pod 条件

Pod有一个 PodStatus，它有一组 PodConditions 。 PodCondition 数组的每个元素都有一个 type 字段和一个 status 字段。

type 字段是字符串，可能的值有 PodScheduled、Ready、Initialized 和 Unschedulable。

status 字段是一个字符串，可能的值有 True、False 和 Unknown。

### Pod 探针

对 Pod 的健康状态检查可以通过两类探针: `Livenessprobe` 和 `ReadinessProbe` 。

**LivenessProbe 探针：** 用于判断容器是否存活（Running 状态），如果 LivenessProbe 探针探测到容器不健康，则 Kubelet 将杀掉该容器，并根据容器的策略做相应的处理。

**ReadinessProbe 探针：** 用于判断容器是否启动完成（Ready 状态)， 可以接受请求。如果 ReadinessProbe 探针检测到失败， 则 Pod 的状态将被修改。Endpoint Controller 将从 Service 的 Endpoint 中删除包含该容器所在的 Pod 的 Endpoint。

kubelet 可以对以上两种探针执行和做出反应，有三种结果如下：

**Success:** 通过检查。
**Failure:** 未通过检查。
**Unknown:** 检查失败, 不采取任何措施。

探针的类型有三种：

ExecAction：在容器内执行指定命令。如果命令退出时返回码为 0 则认为诊断成功。
TCPSocketAction：对指定端口上的容器的 IP 地址进行 TCP 检查。如果端口打开，则诊断被认为是成功的。
HTTPGetAction：对指定的端口和路径上的容器的 IP 地址执行 HTTP Get 请求。如果响应的状态码大于等于 200 且小于 400，则诊断被认为是成功的。

> 什么时候使用这两种探针？
1. 如果容器中的进程在运行时遇到问题自行崩溃，则不一定需要 `LivenessProbe` ; kubelet 将根据 Pod 的 restartPolicy 自动执行正确的操作。
2. 如果您希望容器在探针失败时被杀死并重新启动，请指定一个 `LivenessProbe` ，并指定 restartPolicy 为 `Always` 或 `OnFailure`。
3. 如果要仅在探测成功时才开始向 Pod 发送流量，请指定 `ReadinessProbe`。在这种情况下，`ReadinessProbe` 与 `LivenessProbe`，但是设置了 `ReadinessProbe` 意味着 Pod 只有在 `ReadinessProbe` 探针探测成功后才开始接收流量。
4. 如果容器在启动过程中加载大量数据，您可以指定一个 `ReadinessProbe`。
5. 如果您希望容器能够自行维护，您可以指定一个 `ReadinessProbe`，该探针检查与 `LivenessProbe` 不同的入口。
6. 如果您只是想在删除 Pod 时，禁止流量访问到该 Pod ，则不一定需要 `ReadinessProbe`; 在删除时，无论 `ReadinessProbe` 是否存在，Pod 自动将其置于未就绪状态。在 Pod 等待 Pod 中的 Containers 停止时，Pod保持未就绪状态。

### 重启策略
PodSpec 中有一个 `restartPolicy` 字段，可能的值为 `Always`、`OnFailure` 和 `Never`。默认为 `Always`。 `restartPolicy` 适用于 Pod 中的所有容器。`restartPolicy` 仅指通过同一节点上的 `kubelet` 重新启动容器。失败的容器由 `kubelet` 以五分钟为上限的指数退避延迟（10秒，20秒，40秒…）重新启动，并在成功执行十分钟后重置。一旦绑定到一个节点，Pod 将永远不会重新绑定到另一个节点。



## Pod API

Pod 常用 API
```
---
#版本号
apiVersion: v1
#资源类型
kind: Pod
#元数据
metadata:
  #Pod名称，命名符合RFC 1035规范
  name: string
  #命名空间
  namespace: string
  #自定义标签列表
  labels:
    - name: string
  #自定义注解列表
  annotations:
    - name: string
#Pod中容器的详细定义
sepc:
  #容器列表
  containers:
  #容器的名称
  - name: string
    #容器镜像名称
    image: string
    #获取镜像的策略
    imagePullPolicy: [Always | Never | IfNotPresent ]
    #容器的启动命令列表
    command: [string]
    #容器的启动命令参数列表
    args: [string]
    #容器的工作目录
    workingDir: string
    #挂在到容器卷内部的存储卷配置
    volumeMounts:
    #引用 Pod 定义的共享存储卷的名称，需使用 volumes 部分定义的共享存储卷的名称
    - name: string
      #存储卷内mount的绝对路径，应少于512字符
      mountPath: string
      #是否为只读模式，默认为读写模式
      readOnly: boolean
    #容器要暴露的端口列表
    ports:
    #端口的名称
    - name: string
      #容器需要监听的端口号
      containerPort: int
      #容器所在主机要监听的端口号
      hostPort: int
      #端口协议，支持TCP/UDP
      protocol: string
    #容器运行时注入的环境变量列表
    env:
    #环境变量的名字
    - name: string
      #环境变量的值
      value: string
    #资源限制和资源请求
    resources:
      #资源限制
      limits:
        # CPU限制，单位为core 数，将用于docker run --cpu-shares 参数
        cpu: string
        # 内存限制，将用于 docker run --memory 参数
        memory: string
      #资源请求
      requests:
        #CPU 请求， 容器启动的初始可用数
        cpu: string
        #内存请求， 容器启动的初始可用数
        memory: string
    #对容器内的健康检查设置
    livenessProbe:
      #对容器的检查设置 exec 方式
      exec:
        #指定命令或脚本
        command: [string]
      #对容器内健康检查设置 httpGet 方式
      httpGet:
        path: string
        port: number
        host: string
        scheme: string
        httpHeaders:
        - name: string
          value: string
      #对容器健康检查tcpsocket方式
      tcpSocket:
        port: number
      #容器启动完成后首次探测时间
      initialDelaySeconds: 0
      #对容器健康检查的探测等待时间，单位为s，默认为1s，超过该时间设置，认为容器不健康，重启容器
      timeoutSeconds: 0
      #对容器健康检查探测时间设置，默认10s探测一次
      periodSeconds: 0
      successThreshold: 0
      failureThreshold: 0
    securityContext:
      privileged: false
  #pod的重启策略，同docker
  restartPolicy: [Always | Never | OnFailure]
  #表示pod将调度到包含这些label的node上
  nodeSelector: object
  #pull镜像时使用的secret名称，
  imagePullSecrets:
  - name: string
  #是否使用主机网络模式，默认为false
  hostNetWork: false
  #在该pod上定义的共享存储卷列表
  volumes:
  #存储卷的名称
  - name: string
    #类型为emptyDir 的卷，还可以指定其他的类型
    emptyDir: { }
    #表示挂载pod所在的宿主机目录
    hostPath:
      Path: string
    #secret类型的存储卷，挂在集群预定义的secret对象内部
    secret:
      secretName: string
      items:
      - key: string
        path: string
    #类型为configMap的卷，表示挂载集群预定义的configMap对象到容器内部
    configMap:
      name: string
      items:
      - key: string
        path: string
```


## Pod 简单运行示例
运行一个简单的 Hello World Pod

```
cat<<'EOF'> hello-pod.yml
apiVersion: v1
kind: Pod
metadata:
  name: pod-example
spec:
  containers:
  - name: alpine
    image: alpine:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo hello; sleep 10;done"]
EOF
kubectl create -f hello-pod.yml
```
可以看到 pod 的状态,在拉取镜像中
```
[root@kubernetes ~]# kubectl get pod
NAME          READY     STATUS              RESTARTS   AGE
pod-example   0/1       ContainerCreating   0          5s
```
创建完成之后的状态为
```
[root@kubernetes ~]# kubectl get pod
NAME          READY     STATUS    RESTARTS   AGE
pod-example   1/1       Running   0          2m
```




