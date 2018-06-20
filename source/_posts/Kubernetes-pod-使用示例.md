---
title: Kubernets Pod 使用示例
date: 2018-06-20 15:00:40
tags:
categories:
- kubernetes
---


## Kubernets Pod 的使用

通过 [Kubernets 资源对象之 pod](https://kuops.com/2018/06/11/Kubernetes-%E8%B5%84%E6%BA%90%E5%AF%B9%E8%B1%A1%E4%B9%8BPod/) 已经了解到 Pod 是什么，现在我们通过运行 Pod 了解一下  Pod 的具体用法。

## 静态 Pod

静态 `pod` 直接运行节点上的 `kubelet` 进程来管理，不经过 master 节点上的 API 服务器。当 `pod` 崩溃时会自动重启该 `pod`。静态 `pod` 没有健康检查。静态 `pod` 始终运行在同一个节点上。

`Kubelet` 自动为每一个静态 `pod` 在 Kubernetes 的 API 服务器上创建一个镜像 Pod（Mirror Pod），因此可以在 API 服务器查询到该 pod，但是不被 API 服务器控制（例如不能删除）。

静态 `pod` 有两种创建方式：用配置文件或者通过 HTTP：


### 1. 使用 conf 方式

kubelet 启动时增加 `--pod-manifest-path=/etc/kubelet.d/` 参数。
```
mkdir -p /etc/kubernetes/manifests
```
定义配置文件并启动
```
cat <<EOF> /etc/kubernetes/manifests/static-web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    role: myrole
spec:
  containers:
    - name: web
      image: nginx
      ports:
        - name: web
          containerPort: 80
          protocol: TCP
EOF
#已经运行
[root@kubernetes ~]# kubectl   get pod
NAME                    READY     STATUS    RESTARTS   AGE
static-web-kubernetes   1/1       Running   0          2m
```
如果删除该文件，则对应 Pod 也会自动删除
```
rm -f /etc/kubernetes/manifests/static-web.yaml
#已经删除
[root@kubernetes ~]# kubectl   get pod
No resources found.
```

### 2. 使用 HTTP 

Kubelet 周期地从 `--manifest-url=` 参数指定的地址下载文件，并且把它翻译成 `JSON/YAML` 格式的 `pod` 定义。此后的操作方式与 `--pod-manifest-path=` 相同，kubelet 会不时地重新下载该文件，当文件变化时对应地终止或启动静态pod。

## Pod 运行多个容器

两个镜像的 Dockerfile 都在我的仓库中 https://github.com/kuops/Dockerfiles.git

创建 pod
```
cat > nginx-flask-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-flask
  labels:
    name: nginx-flask
spec:
  containers:
  - name: nginx
    image: kuops/mynginx
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 80
      hostPort:  80
  - name: flask
    image: kuops/myflask
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 5000
EOF
kubectl create -f nginx-flask-pod.yaml
```
由于使用 hostport 模式访问，通过参数 `-o wide`,找到 pod 所在节点，之后进行访问
```
[root@kubernetes ~]# kubectl  get pod -o wide
NAME          READY     STATUS    RESTARTS   AGE       IP           NODE
nginx-flask   2/2       Running   0          2m        10.244.1.8   node1

[root@kubernetes ~]# curl  node1
Hello Flask!
```
查看 nginx 容器使用的是 `localhost:5000` 访问的
```
[root@kubernetes ~]# kubectl exec -it nginx-flask --container nginx cat /etc/nginx/conf.d/default.conf
server {
listen 80;
    location / {
    proxy_pass      http://localhost:5000/;
    }
}
```

## Pod 中容器共享 volume

使用类型为 `empyDir` 的方式，挂载日志到日志搜集容器，设置的 Volume 名为 `app-logs` ,类型为 `empyDir`,挂载到 tomcat 的 `/usr/local/tomcat/logs` 目录，同时挂载到 logreader 容器内的 `/logs` 目录。 tomcat 容器启动后会向 `/usr/local/tomcat/logs` 写文件， logreader 就可以读取其中的文件了。

```
cat > pod-volume-applogs.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: volume-pod
spec:
  containers:
  - name: tomcat
    image: tomcat
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: app-logs
      mountPath: /usr/local/tomcat/logs
  - name: alpine
    image: alpine
    command: ["sh", "-c", "tail -f /logs/catalina*.log"]
    volumeMounts:
    - name: app-logs
      mountPath: /logs
  volumes:
  - name: app-logs
    emptyDir: {}
EOF
kubectl  create  -f pod-volume-applogs.yaml
```
查看  logreader 输出的内容：
```
kubectl logs volume-pod -c alpine
```
查看 tomcat 中文件的内容
```
kubectl  exec  -it volume-pod -c tomcat ls /usr/local/tomcat/logs
kubectl  exec  -it volume-pod -c tomcat -- tail -f /usr/local/tomcat/logs/catalina.2018-06-19.log
```

## Pod 资源限制

创建一个内存最小请求为 100M 最大为 200 M 的容器。
```
cat <<EOF> memory-request-limit.yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-demo
spec:
  containers:
  - name: memory-demo-ctr
    image: polinux/stress
    resources:
      limits:
        memory: "200Mi"
      requests:
        memory: "100Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
EOF
kubectl  create  -f memory-request-limit.yaml
```
在配置文件中，该 `args` 部分在 `Container` 启动时提供参数。该 `--vm-bytes` , `150M` 参数告诉容器尝试分配的内存 150 MIB。

通过安装 `heapster` 查看资源使用情况

```
[root@kubernetes ~]# kubectl  top pod
NAME          CPU(cores)   MEMORY(bytes)
memory-demo   14m          150Mi
```
测试一下超过内存占用会怎么样
```
cat <<EOF> memory-request-limit2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-demo-2
spec:
  containers:
  - name: memory-demo-2-ctr
    image: polinux/stress
    resources:
      requests:
        memory: "50Mi"
      limits:
        memory: "100Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
EOF
kubectl  create  -f memory-request-limit2.yaml
```
看到 `OOMKilled` ,输出显示容器因内存不足而终止（OOM）。
```
[root@kubernetes ~]# kubectl  get pod
NAME            READY     STATUS      RESTARTS   AGE
memory-demo     1/1       Running     0          5m
memory-demo-2   0/1       OOMKilled   1          6s
```
如果请求一个超过宿主机内存的 pod，则永远处于 pending 状态
```
cat <<EOF> memory-request-limit3.yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-demo-3
spec:
  containers:
  - name: memory-demo-3-ctr
    image: polinux/stress
    resources:
      limits:
        memory: "1000Gi"
      requests:
        memory: "1000Gi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
EOF
kubectl  create  -f memory-request-limit3.yaml
```
查看 Pod 状态
```
[root@kubernetes ~]# kubectl  get pod
NAME            READY     STATUS    RESTARTS   AGE
memory-demo-3   0/1       Pending   0          3s
```
查看有关Pod的详细信息，包括事件：
```
kubectl describe pod memory-demo-3 --namespace=mem-example
```
输出显示由于节点上的内存不足，无法调度Container：
```
Events:
  ...  Reason            Message
       ------            -------
  ...  FailedScheduling  No nodes are available that match all of the following predicates:: Insufficient memory (3).

```
内存资源以字节为单位进行测量。您可以将内存表达为普通整数或具有以下后缀之一的定点整数：E，P，T，G，M，K，Ei，Pi，Ti，Gi，Mi，Ki。例如，以下代表大致相同的值：
```
128974848, 129e6, 129M , 123Mi
```
创建一个限制 CPU 资源的请求, `-cpus "2"`参数告诉 Container 尝试使用 `2 cpus`。`0.5` 同样可以用 `500m` 表示。
```
cat <<'EOF'> cpu-request-limit.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cpu-demo
spec:
  containers:
  - name: cpu-demo-ctr
    image: vish/stress
    resources:
      limits:
        cpu: "1"
      requests:
        cpu: "0.5"
    args:
    - -cpus
    - "2"
EOF
kubectl create  -f cpu-request-limit.yaml
```

## init 容器

Init 容器先于其他容器运行，必须等 init 容器运行完成，再启动其他容器，如果 Pod 的 Init 容器失败，Kubernetes 会不断地重启该 Pod，直到 Init 容器成功为止。然而，如果 Pod 对应的 `restartPolicy` 为 `Never`，它不会重新启动。Init 容器支持应用容器的全部字段和特性，包括资源限制、数据卷和安全设置。 然而，Init 容器对资源请求和限制的处理稍有不同， Init 容器不支持 Readiness Probe，因为它们必须在 Pod 就绪之前运行完成。

如果为一个 Pod 指定了多个 Init 容器，那些容器会按顺序一次运行一个。 每个 Init 容器必须运行成功，下一个才能够运行。 当所有的 Init 容器运行完成时，Kubernetes 初始化 Pod 并像平常一样运行应用容器。

由于 Init Containers 具有独立于应用程序容器的图像，启动相关代码具有如下优势：

*   出于安全原因，它们可以包含并运行不希望包含在应用程序 Container 映像中的实用程序。

*   它们可以包含使用工具和定制化代码来安装，但是不能出现在应用镜像中。例如，代码中需要使用类似 `sed`、 `awk`、 `python` 或 `dig`这样的工具，没必要 From 另一个镜像。

*   应用程序镜像的构建和部署角色可以独立工作，无需共同构建单个应用程序映像。

*   他们使用 Linux 命名空间，以便它们具有来自应用容器的不同文件系统视图。因此，他们可以获得应用程序容器无法访问的 secret 。

*   它们在应用程序容器启动之前运行完毕，并没有与应用容器并行运行，所以 Init 容器提供了一种简单的方式来阻塞或延迟应用容器的启动，直到满足了一组先决条件。

以下是关于如何使用Init Containers的一些想法：

- 等待一个 Service 完成创建，通过类似如下 shell 命令：
```
  for i in {1..100}; do sleep 1; if dig myservice; then exit 0; fi; exit 1
```

- 注册这个 Pod 到远程服务器，通过在命令中调用 API，类似如下：
```
  curl -X POST http://$MANAGEMENT_SERVICE_HOST:$MANAGEMENT_SERVICE_PORT/register -d 'instance=$(<POD_NAME>)&ip=$(<POD_IP>)'
```
- 在启动应用容器之前等一段时间，使用类似 sleep 60 的命令。

- 克隆 Git 仓库到数据卷。

- 将配置值放到配置文件中，运行模板工具为主应用容器动态地生成配置文件。例如，在配置文件中存放 POD_IP 值，并使用 Jinja 生成主应用配置文件。


```
cat <<EOF> init-containers.yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: workdir
      mountPath: /usr/share/nginx/html
  # These containers are run during pod initialization
  initContainers:
  - name: install
    image: busybox
    command:
    - wget
    - "-O"
    - "/work-dir/index.html"
    - http://kubernetes.io
    volumeMounts:
    - name: workdir
      mountPath: "/work-dir"
  dnsPolicy: Default
  volumes:
  - name: workdir
    emptyDir: {}
EOF
kubectl create -f init-containers.yaml
```
如果使用 `kubectl get pod init-demo` 看到已经运行，则可进入容器中，执行如下命令
```
apt-get update
apt-get install curl -y
curl -s localhost|grep '<p>Kubernetes is'
```

## 使 pod 在指定节点运行

将 Kubernetes Pod 分配给 Kubernetes 集群中的特定节点。

查询节点
```
[root@kubernetes ~]# kubectl get node
NAME         STATUS    ROLES     AGE       VERSION
kubernetes   Ready     master    18h       v1.10.4
node1        Ready     <none>    18h       v1.10.4
```

选择一个节点，并添加一个标签
```
kubectl label nodes kubernetes disktype=ssd
```
可以查看 node 节点的标签
```
[root@kubernetes ~]# kubectl get node --show-labels
NAME         STATUS    ROLES     AGE       VERSION   LABELS
kubernetes   Ready     master    23h       v1.10.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,disktype=ssd,kubernetes.io/hostname=kubernetes,node-role.kubernetes.io/master=
node1        Ready     <none>    23h       v1.10.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/hostname=node1
```
创建 Pod
```
cat <<EOF> pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  nodeSelector:
    disktype: ssd
EOF
kubectl create -f pod.yaml
```
查看 pod  所在节点
```
[root@kubernetes ~]# kubectl  get pod -o wide
NAME        READY     STATUS    RESTARTS   AGE       IP            NODE
init-demo   1/1       Running   0          16m       10.244.1.41   node1
nginx       1/1       Running   0          10s       10.244.0.10   kubernetes
```

## 从私有仓库拉取镜像

首先登陆 docker 仓库
```
docker login
```
登陆之后会生成 config.json
```
[root@kubernetes ~]# cat ~/.docker/config.json
{
        "auths": {
                "https://index.docker.io/v1/": {
                        "auth": "x.x.x.x"
                }
        },
        "HttpHeaders": {
                "User-Agent": "Docker-Client/18.03.1-ce (linux)"
        }
}
```
创建一个 secret,名为 `regcred`
```
kubectl create secret docker-registry regcred --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```

- `<your-registry-server>` 是您的私有Docker注册表FQDN，上面 auth 字段的网址
- `<your-name>` 是您的 Docker 用户名。
- `<your-pword>` 是您的 Docker 密码。
- `<your-email>` 是您的 Docker 电子邮件。

查看生成的 secret
```
kubectl get secret regcred --output=yaml
```
拉取镜像
```
cat <<EOF> private-reg-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-reg
spec:
  containers:
  - name: private-reg-container
    image: kuops/secret-demo
  imagePullSecrets:
  - name: regcred
EOF
kubectl create -f private-reg-pod.yaml
```
## 健康检查

kubelet 使用 liveness probe（存活探针）来确定何时重启容器。例如，当应用程序处于运行状态但无法做进一步操作，liveness 探针将捕获到 deadlock，在这种状态下重新启动容器可以帮助尽可能使应用程序更易于使用。

Kubelet 使用 readiness probe（就绪探针）来确定容器是否已经就绪可以接受流量。只有当 Pod 中的容器都处于就绪状态时 kubelet 才会认定该 Pod处于就绪状态。该信号的作用是控制哪些 Pod应该作为service的后端。如果 Pod 处于非就绪状态，那么它们将会被从 service 的 load balancer 中移除。

### exec 方法

```
cat <<EOF> exec-liveness.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness
  name: liveness-exec
spec:
  containers:
  - name: liveness
    image: busybox
    args:
    - /bin/sh
    - -c
    - touch /tmp/healthy; sleep 30; rm -rf /tmp/healthy; sleep 600
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
EOF
kubectl create -f exec-liveness.yaml
```
在配置文件中，您可以看到 `Pod` 有一个 `Container`。该 `periodSeconds` 字段指定该 `kubelet` 应每5秒执行一次活性探测。该 `initialDelaySeconds` 字段告诉 `kubelet` 在执行第一次探测之前应等待 5 秒钟。

要执行探测，kubelet 将在容器中执行 `cat /tmp/healthy` 命令。如果命令成功，返回值为 0，则 kubelet 认为容器是健康的。如果该命令返回一个非零值，则 kubelet 杀死容器并重新启动它。

当容器启动时，它执行这个命令：
```
/bin/sh -c "touch /tmp/healthy; sleep 30; rm -rf /tmp/healthy; sleep 600"
```
在Container的生命的前30秒内，有一个 `/tmp/healthy` 文件。因此，在前 30 秒内，该命令 `cat /tmp/healthy` 返回一个成功代码。30 秒后，`cat /tmp/healthy` 返回失败代码。

使用 kubectl describe 可以看到容器杀死并重建
```
kubectl describe pod liveness-exec
```
输入如下：
```
Events:
  Type     Reason                 Age               From               Message
  ----     ------                 ----              ----               -------
  Normal   Scheduled              2m                default-scheduler  Successfully assigned liveness-exec to node1
  Normal   SuccessfulMountVolume  2m                kubelet, node1     MountVolume.SetUp succeeded for volume "default-token-j7gsz"
  Warning  Unhealthy              47s (x6 over 2m)  kubelet, node1     Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory
  Normal   Pulling                16s (x3 over 2m)  kubelet, node1     pulling image "busybox"
  Normal   Killing                16s (x2 over 1m)  kubelet, node1     Killing container with id docker://liveness:Container failed liveness probe.. Container will be killed and recreated.
  Normal   Pulled                 15s (x3 over 2m)  kubelet, node1     Successfully pulled image "busybox"
  Normal   Created                15s (x3 over 2m)  kubelet, node1     Created container
  Normal   Started                15s (x3 over 2m)  kubelet, node1     Started container
```

### http 方法

`periodSeconds` 字段指定该 kubelet 应每 3 秒执行一次活性探测, `initialDelaySeconds` 字段告诉kubelet在执行第一次探测之前应等待3秒钟。`kubelet` 会向容器内的 8080 端口发送 http `GET` 请求，如果服务器 `/healthz` 路径的处理程序返回成功代码，则 `kubelet` 会认为Container处于活动状态且健康。如果处理程序返回失败代码，则 `kubelet` 杀死容器并重新启动它。

```
cat <<EOF> http-liveness.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness
  name: liveness-http
spec:
  containers:
  - name: liveness
    image: kubernetes/liveness
    args:
    - /server
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
        httpHeaders:
        - name: X-Custom-Header
          value: Awesome
      initialDelaySeconds: 3
      periodSeconds: 3
EOF
kubectl create -f http-liveness.yaml
```
对于容器 `/healthz` 大于 10 秒,处理程序返回状态 500。
```
http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
    duration := time.Now().Sub(started)
    if duration.Seconds() > 10 {
        w.WriteHeader(500)
        w.Write([]byte(fmt.Sprintf("error: %v", duration.Seconds())))
    } else {
        w.WriteHeader(200)
        w.Write([]byte("ok"))
    }
})
```

### tcp 方法

TCP 检查的配置与 HTTP 检查非常相似。容器启动后5秒钟，kubelet将发送第一个准备就绪探针,如果探针成功，则将标记为已准备就绪。该 `kubelet` 将继续每10秒运行一次该检查,该配置还包括活动探测器。容器启动 15 秒后，`Kubelet` 将运行第一个活性探针。就像就绪探测器一样，它将尝试连接到 goproxy 端口8080上的 容器。如果活动探测失败，容器将重新启动。

```
cat <<EOF> tcp-liveness-readiness.yaml
apiVersion: v1
kind: Pod
metadata:
  name: goproxy
  labels:
    app: goproxy
spec:
  containers:
  - name: goproxy
    image: tomcat
    ports:
    - containerPort: 8080
    readinessProbe:
      tcpSocket:
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
    livenessProbe:
      tcpSocket:
        port: 8080
      initialDelaySeconds: 15
      periodSeconds: 20
EOF
kubectl create -f tcp-liveness-readiness.yaml
```
有时，应用程序暂时无法提供流量。例如，应用程序可能需要在启动过程中加载大型数据或配置文件。在这种情况下，你不想杀死应用程序，但你也不想发送请求。Kubernetes提供准备就绪探测器来检测和缓解这些情况。容器报告说他们没有准备好的吊舱不会通过Kubernetes服务收到流量。

准备探测器的配置与活性探测器类似。唯一的区别是你使用readinessProbe字段而不是livenessProbe字段。
```
readinessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  initialDelaySeconds: 5
  periodSeconds: 5
```

> 探针的其他字段，查看 https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/

## pod 和 容器的上下文

### pod 的安全上下文

要指定 `Pod` 的安全设置，请 `securityContext` 在Pod规范中包含该字段。该 `securityContext` 字段是一个 `PodSecurityContext` 对象。您为 Pod 指定的安全设置适用于Pod中的所有容器。以下是具有卷securityContext和emptyDir卷的Pod的配置文件：

```
cat <<EOF> security-context.yaml
apiVersion: v1
kind: Pod
metadata:
  name: security-context-demo
spec:
  securityContext:
    runAsUser: 1000
    fsGroup: 2000
  volumes:
  - name: sec-ctx-vol
    emptyDir: {}
  containers:
  - name: sec-ctx-demo
    image: kuops/node-hello:1.0
    volumeMounts:
    - name: sec-ctx-vol
      mountPath: /data/demo
    securityContext:
      allowPrivilegeEscalation: false
EOF
kubectl create -f security-context.yaml
```

获取运行Container的shell：
```
kubectl exec -it security-context-demo -- sh
```

在你的shell中，列出正在运行的进程：
```
ps aux
```
输出显示进程正在以用户 1000 身份运行，这是以下值 `runAsUser`：
```
USER   PID %CPU %MEM    VSZ   RSS TTY   STAT START   TIME COMMAND
1000     1  0.0  0.0   4336   724 ?     Ss   18:16   0:00 /bin/sh -c node server.js
1000     5  0.2  0.6 772124 22768 ?     Sl   18:16   0:00 node server.js
```
在你的shell中，导航到/data并列出一个目录：
```
cd /data
ls -l
```
输出显示该/data/demo目录具有组ID 2000，该值是fsGroup。
```
drwxrwsrwx 2 root 2000 4096 Jun  6 20:08 demo
```
在你的 shell中，进入 /data/demo 并创建一个文件：
```
cd demo
echo hello > testfile
```

列出目录中的文件/data/demo：
```
ls -l
```
输出显示testfile具有组ID 2000，它是的值fsGroup。
```
-rw-r--r-- 1 1000 2000 6 Jun  6 20:08 testfile
```

### 容器的安全上下文

```
cat <<EOF> security-context-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: security-context-demo-2
spec:
  securityContext:
    runAsUser: 1000
  containers:
  - name: sec-ctx-demo-2
    image: kuops/node-hello:1.0
    securityContext:
      runAsUser: 2000
      allowPrivilegeEscalation: false
EOF
kubectl create -f security-context-2.yaml
```
同样 `ps aux` 查看到的运行用户是 2000
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
2000         1  0.0  0.0   4336   764 ?        Ss   20:36   0:00 /bin/sh -c node server.js
2000         8  0.1  0.5 772124 22604 ?        Sl   20:36   0:00 node server.js
...
```


