---
title: 使用 WSL 操作 Docker
date: 2018-05-14 12:22:20
tags:
---

## 设置 WSL 使用 Docker

通过一些调整，WSL（ Windows Subsystem for Linux ）可以用于 `Docker for Windows`。

### 设置 Windowos 的 Docker

打开设置，使 Docker 守护程序监听在 TCP 端口。WSL 通过 TCP 连接操作 Docker。

![](/img/wsl-docker/1.png)

如果想永久存储数据，设置以下选项：

![](/img/wsl-docker/2.png)


### 在WSL中安装Docker

使用 Ubuntu Bash 运行以下脚本

```
cat <<'EOF'> deploy-docker.sh
#!/bin/bash
# Environment variables you need to set so you don't have to edit the script below.
DOCKER_CHANNEL=edge
DOCKER_COMPOSE_VERSION=1.20.1

# setting apt-get mirrors
sudo sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list

# Update the apt package index.
sudo apt-get update

# Install packages to allow apt to use a repository over HTTPS.
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

# Add Docker's official GPG key.
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -

# Verify the fingerprint.
sudo apt-key fingerprint 0EBFCD88

# Pick the release channel.
sudo add-apt-repository \
   "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
   $(lsb_release -cs) \
   ${DOCKER_CHANNEL}"

# Update the apt package index.
sudo apt-get update

# Install the latest version of Docker CE.
sudo apt-get install -y docker-ce

# Allow your user to access the Docker CLI without needing root.
sudo usermod -aG docker $USER

# Install Docker Compose.
sudo curl -L https://get.daocloud.io/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose &&
sudo chmod +x /usr/local/bin/docker-compose
EOF
```

运行脚本
```
sudo sh deploy-docker.sh
```

### 将 WSL 连接到 Docker for Windows

添加到 ~/.bashrc
```
sed -i '$a\export DOCKER_HOST=tcp://0.0.0.0:2375' ~/.bashrc
source ~/.bashrc
```

### 将 Windows Docker 卷与 Linux 对应

在 WSL 中，卷格式为 `/c/Users/myapp` , 为了能够正常工作需要稍作更改。

```
sudo mkdir /c
sudo mount --bind /mnt/c /c
```

为所有共享的磁盘重复这样挂载操作，如果挂载成功使用 `ls -la /c` 与 `ls -la /mnt/c` 输出结果相同。

对于运行 `docker-compose up` 需要进入 `/c/compose-dir` 而不是 `/mnt/c/compose-dir`。


### 自动绑定安装

调整 visudo , 替换 `yourname` 为 whoami 命令返回结果
```
echo "sudo mount --bind /mnt/c /c" >> ~/.bashrc
sudo sed -i '$a\yourname ALL=(root) NOPASSWD: /bin/mount' /etc/sudoers
source ~/.bashrc
```

## 设置 WSL 操作 Kubernets

原理跟上面的 Docker 差不多，首先去用户家目录复制 `.kube` 文件夹到 WSL 的家目录
```
 cp -rp /mnt/c/Users/your_username/.kube/ ~
```

下载 Kubectl 客户端并安装

```
wget https://dl.k8s.io/v1.9.6/kubernetes-client-linux-amd64.tar.gz
tar xf kubernetes-client-linux-amd64.tar.gz
sudo mv kubernetes/client/bin/kubectl  /usr/local/bin/
echo "source <(kubectl completion bash)" >> ~/.bashrc
```

测试
```
kubectl run  --image=nginx nginx
kubectl expose deployment nginx --port=80 --target-port=80 --type=LoadBalancer
```

访问， 也可通过浏览器直接访问

```
hsy@kuops:~$ curl  -I localhost
HTTP/1.1 200 OK
Server: nginx/1.13.12
Date: Sun, 15 Apr 2018 14:09:47 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Mon, 09 Apr 2018 16:01:09 GMT
Connection: keep-alive
ETag: "5acb8e45-264"
Accept-Ranges: bytes
```
