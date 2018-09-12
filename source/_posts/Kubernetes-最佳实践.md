---
title: Kubernetes 的最佳实践
date: 2018-09-12 23:29:40
tags:
categories:
- kubernetes
---


## Kubernetes的最佳实践

此演讲稿中的最佳实践源于 Sandeep 及其团队关于您可以在 Kubernetes 中执行相同任务的许多不同方式的讨论。他们编制了一份这些任务的清单，并从中衍生出一套最佳实践。

最佳实践分为：

1. 建筑容器
2. 容器内部
3. 部署
4. 服务
5. 应用架构


## 1. 构建容器

### 不要轻易相信任何镜像

人们将从 DockerHub 中获取某人创建的基础图像，因为乍一看它有他们需要的包，随后将其选择的容器推送到生产环境中。


这有很多错误：您可能使用了具有漏洞的错误代码版本，其中存在错误，或者更糟糕的是它可能会故意捆绑恶意软件，您只是不知道。


### 保持基础镜像最小化

基于最精简的基础镜像，从顶部开始构建软件包，这样你就知道镜像里面全部内容。

较小的基础映像也可以减少开销。您的应用程序可能只有大约 5 MB，但如果您盲目地使用现成的图像，例如 Node.js，它包含一个额外的 600MB 库，而您不需要。


较小图像的其他优点：

- 更快的构建
- 存储量减少
- 镜像拉取更快
- 攻击面可能较小

### 编译和运行镜像分开

此模式对于编译对 Go 和 C++ 或 Typescript for Node.js 的静态语言更有用，分为构建容器和运行时容器。

在这种模式中，您将拥有一个包含编译器，依赖项和单元测试的构建容器。然后通过运行构建容器构建出需要的构建产物。它将静态文件，包，代码等组合在一起，最后通过运行时容器运行，该容容器也可以包含一些监视或调试工具。

```
FROM golang:1.7.3
WORKDIR /go/src/github.com/alexellis/href-counter/
RUN go get -d -v golang.org/x/net/html  
COPY app.go .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

FROM alpine:latest  
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=0 /go/src/github.com/alexellis/href-counter/app .
CMD ["./app"]
```

第二个 `FROM` 指令以 `alpine:latest` 图像为基础开始一个新的构建阶段。该 `COPY --from=0` 行仅将前一阶段的构建工件复制到此新阶段。Go SDK 和任何中间工件都被遗忘，而不保存在最终图像中。

## 2. 容器内部

### 在容器内使用非root用户

如果在容器内部使用 root 用户的话，需要将用户更改为非 root 用户。

原因是，如果有人攻击您的容器并且您没有从 root 更改为普通用户，那么简单的容器逃逸可以让他们以 root 用户访问您的宿主机。当您将用户更改为非 root 用户时，黑客需要额外的尝试才能获得 root 访问权限

在 Kubernetes 中，您可以通过设置安全性上下文 `runAsNonRoot: true` 来强制执行此操作，以下配置实例对 pod 生效。

```
apiVersion: v1  
kind: Pod  
metadata:  
  name: hello-world  
spec:  
  containers:  
  # specification of the pod’s containers  
  # ...  
  securityContext:  
    readOnlyRootFilesystem: true  
    runAsNonRoot: true
```

### 文件系统只读

通过设置 `readOnlyRootFilesystem: true` 生效

### 每个容器一个进程

您可以在容器中运行多个进程，但建议只运行一个进程。这是由 orchestrator 的工作方式决定的。Kubernetes 根据单个进程是否健康来管理容器。如果你在一个容器里面有20个进程，它如何知道容器是否健康呢？

### 应当让容器中的进程需要错误返回错误码，并退出，而不是继续运行

Kubernetes 为您重新启动失败的容器，因此您应该使用错误代码使程序彻底崩溃，以便他们可以在没有您干预的情况下成功重新启动，当前你也可以使用 pod 的 restartPolicy 根据探针的结果进行重启。


### 将所有的输出打印到到 stdout 和 stderr

默认情况下，Kubernetes 会侦听这些管道并将输出发送到您的日志记录服务。

## 3. Deployment

### 使用 `--record` 选项可以更轻松地回滚

应用yaml时，请使用--record标志：

```
kubectl apply -f deployment.yaml --record
```

使用此选项，每次有更新时，它都会保存到这些部署的历史记录中，并使您能够回滚更改。

![](https://images.contentstack.io/v3/assets/blt300387d93dabf50e/blt42e000d51356716d/5b8462f6c44e2f610ba7c7bd/download)

### 使用大量描述性标签

由于标签是任意键值对，因此它们非常强大。例如，考虑下面的图表，名为'Nifty'的应用程序分布在四个容器中。使用标签，您可以通过选择后端


![](https://images.contentstack.io/v3/assets/blt300387d93dabf50e/blteae056bbbd42d417/5b8463070cdef43e0b861e3b/download)

### 使用 sidecar 模式来进行代理，监视

有时您需要一组进程来相互通信。但是你不希望所有这些都在一个容器中运行，（参见上面“每个容器一个进程”），而是在Pod中运行相关进程。

同样，当您运行的进程需要依赖另一个程序时，例如，您的进程所依赖的数据库，而您不虚要把凭据存入到每个容器中，相反可以使用 sidecar 模式来启动代理容器负责管理数据库连接。


### 不要使用 sidecars 进行启动引导

虽然 sidecars 非常适合处理集群内外的请求，但 Sandeep 不建议使用它们进行自举。在过去，bootstrapp 是唯一的选择，但现在 Kubernetes 有 `init containers`。

当容器里面的一个进程依赖于其它的一个微服务时，你可以使用 init 容器一直等待两个进程同时启动再启动容器。这可以防止在进程和微服务不同步时发生大量错误。


基本上规则是：对于始终发生的事件使用 sidecars ，对于一次性事件使用init容器。


### 不要使用：latest 或没有标签

这个很明显，大多数人今天也这样做了。如果您没有为容器添加标记，它将始终尝试从存储库中提取最新的标记，这可能包含也可能不包含您认为具有的更改。


### Readiness and Liveness 是你的朋友

可以使用探测器，以便 Kubernetes 知道节点是否健康以及是否应该向其发送流量。默认情况下，Kubernetes 会检查进程是否正在运行。但是通过使用探针，您可以利用 Kubernetes 中的这种默认行为来添加自己的逻辑。

![](https://images.contentstack.io/v3/assets/blt300387d93dabf50e/blt6000508012c0e26f/5b846323acedd45c0bf7c540/download)


## 4. Service

### 不要使用 LoadBalancer 类型

每次你在部署文件里面加一个公有云提供商的 loadbalancer（负载均衡器）的时候，它都会创建一个。 它确实是高可用，速度快，但它需要花钱。

提示：使用 Ingress 代替，可让您通过单个端点对多个服务进行负载均衡。这不仅更简单，而且更便宜。

当然，这种策略只有在您使用 http 或 Web 内容时才有效，并且不适用于基于UDP或TCP的应用程序。

### Nodeport 类型足够好

这更多是个人偏好，并非所有人都推荐这一点。NodePort把你的应用通过一个VM的特定端口暴露到外网上。 问题就是它没有像负载均衡器那样有高可用。比如极端情况，VM挂了你的服务也挂了。


### 将外部服务映射到内部服务

这是大多数人不知道你可以在Kubernetes做的事情。如果您需要群集外部的服务，您可以使用类型为ExternalName的服务。现在您可以通过名称调用服务，Kubernetes管理器将您传递给它，就好像它是集群的一部分一样。如果服务位于同一网络上，Kubernetes会将服务视为服务，但它实际上位于服务之外。

```
kind: Service
apiVersion: v1
metadata:
  name: my-service
  namespace: prod
spec:
  type: ExternalName
  externalName: my.database.example.com
```

查找主机时 `my-service.prod.svc.CLUSTER`，群集 DNS 服务将返回 `CNAME` 包含该值的记录 `my.database.example.com`。访问 my-service工作的方式与其他服务相同，但重要的区别在于重定向发生在 DNS 级别，而不是通过代理或转发。如果您以后决定将数据库移动到群集中，则可以启动其 pod，添加适当的选择器或端点，以及更改服务 type。


## 5. 应用程序架构

### 使用 helm charts

Helm 基本上是打包 Kubernetes 配置的存储库。如果要部署 MongoDB 。它有一个预配置的 Helm 图表，其中包含所有依赖项，您可以轻松地将其部署到集群中。

###  所有下游依赖项都不可靠

您的应用程序中应包含逻辑和错误消息，以说明您无法控制的任何依赖项。Sandeep建议，为了帮助您进行下游管理，您可以使用像 Istio 或 Linkerd 这样的服务网格。

### 确保您的微服务不是太微

您需要逻辑组件，而不是每个功能都变成微服务。


### 使用命名空间来拆分群集

例如，您可以在具有不同命名空间的同一群集中创建 Prod，Dev 和 Test，还可以使用命名空间来限制资源量，以便一个错误进程不会使用所有群集资源。

### 基于角色的访问控制

作为最佳实践安全措施，制定适当的访问控制以限制对群集的访问量。


原文来自： https://www.weave.works/blog/kubernetes-best-practices
