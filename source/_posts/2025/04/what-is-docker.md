---
title: 什么是Docker
date: 2025-04-15 23:06:20
tags:
    - Docker
categories:
    - 技术介绍
---

Docker是一个开源的轻量级容器平台，可以将应用及其依赖打包在Docker中，实现快速部署和跨环境运行。
<!-- more --> 

# Docker的核心组件
Docker基于B/S架构，其核心组件包括
1. Docker Client
2. Docker Daemon
3. Docker Image
4. Docker Register
5. Docker Container

## Docker Client
用于发起各种请求，如`docker run`、`docker build`等等。最常用的 Docker 客户端就是 docker 命令和[docker desktop](https://www.docker.com/products/docker-desktop/)。

## Dokcer Deamon
又称之为docker的核心进程，该进程会提供一个**API Server**（API Server是Deamon的一部分），负责接收来自docker client的请求，API Server 将通过Docker daemon 内部的一个**路由**分发调度，将请求路由到Daemon中对应的处理函数**handler**，handler再调用底层逻辑完成请求响应，并通过API Server返回响应。

Handler调用底层逻辑时，会交由处理引擎engine创建指定的job，job中绑定了具体的功能函数，完成处理逻辑。

Job 实际上是封装了对某个具体任务的调用。docker Daemon 启动时，会注册各种 Job：
```go
// src/github.com/docker/docker/daemon/daemon.go

func (daemon *Daemon) Install(eng *engine.Engine) error {
    eng.Register("create", daemon.ContainerCreate)
    ...
}
```

Handler在运行时创建Job完成处理逻辑：
```go
job := eng.Job("create", args...)
if err := job.Run(); err != nil {
    return err
}
```

docker deamon的结构可以分为三个部分：
* Docker Server，包括API Server、Router、Handler
* Engine
* Job

Docker Daemon 可以认为是通过 Docker Server 模块接受 Docker Client 的请求，并在 Engine 中处理请求，然后根据请求类型，创建出指定的 Job 并运行。 Docker Daemon 运行在 Docker host 上，负责创建、运行、监控容器，构建、存储镜像。

Docker Deamon的架构图如下所示：

{% asset_img docker架构图.jpeg Docker架构图 %}

Job运行过程的作用有以下几种可能：

向 Docker Registry 获取镜像
* 通过 graphdriver 执行容器镜像的本地化操作
* 通过 networkdriver 执行容器网络环境的配置
* 通过 execdriver 执行容器内部运行的执行工作

## Docker Image
Docker 镜像可以看作是一个特殊的文件系统，除了提供容器运行时所需的程序、库、资源、配置等文件外，还包含了一些为运行时准备的一些配置参数（如匿名卷、环境变量、用户等）。镜像不包含任何动态数据，其内容在构建之后也不会被改变。我们可将 Docker 镜像看成只读模板，通过它可以创建 Docker 容器。

我们可以将镜像的内容和创建步骤描述在一个文本文件中，这个文件被称作 Dockerfile ，通过执行 docker build \<docker-file> 命令可以构建出 Docker 镜像。

## Docker Register
Docker registry 是存储 docker image 的仓库，运行docker push、docker pull、docker search时，实际上是通过 docker daemon 与 docker registry 通信。

## Docker Container
Container是Image运行的一个实例，是Image的运行时，是真正运行项目程序、消耗系统资源、提供服务的地方。

# 什么是Dockerfile
Dockerfile是自动构建docker的配置文件，定义了docker image构建的流程。

## Dockerfile主要结构

一般来说，一个dockerfile文件包含四个内容：
1. 基础镜像信息指令 FROM。
2. 声明Image元信息（不只是创作者）的指令 LABEL.
3. 镜像操作指令RUN 、 EVN 、 ADD 和 WORKDIR 等
4. 镜像构建指令CMD 、 ENTRYPOINT 和 USER 等

下面是一段简单的Dockerfile的例子：
```dockerfile
FROM python:3.7
MAINTAINER qxp <xiaopengqiu8@gmail.com>
COPY . /app
WORKDIR /app
RUN pip install -r requirements.txt
EXPOSE 5000
# 设置容器启动时执行的主程序为 python
ENTRYPOINT ["python"] 
# CMD 会作为参数传给 ENTRYPOINT，结合起来就是 python app.py
CMD ["app.py"] 
```

## Dockerfile的常见命令

### FROM
每个镜像都必须基于基础镜像构建，FROM 用于指定其父镜像。其中`FROM scratch`表示父镜像为空镜像，若不需要基于基础镜像构建，仍然需要用 FROM 进行指定。

```dockerfile
FROM python:3.7
```

### LABEL
用于指定镜像的元数据，使用Key-Value标签，支持设定多个元数据。

```dockerfile
LABEL maintainer="Angel_Kitty <angelkitty6698@gmail.com>"
LABEL version="1.0"
LABEL description="A cool Python app"
```
注意事项：
* 多次定义相同的 key，后面的会覆盖前面的

### COPY、ADD
这两个命令都是将**本地主机文件**复制到指定**容器**中指定位置。
但ADD支持将压缩包**自动解压**以及**远程下载**文件。

```dockerfile
COPY requirements.txt /app/
ADD hello.txt /app/hello.txt
ADD app.tar.gz /app/
ADD https://example.com/file.zip /tmp/
```

### ENV
设置镜像的环境变量。
```dockerfile
ENV NODE_ENV=prod
```

### ARG
设置构建镜像时的默认参数，设置后无需在build时用命令行传入参数。
```dockerfile
ARG APP_VERSION=1.0
```

### WORKDIR
设置当前工作路径，相当于`cd`。WORKDIR可以设置多次，既可以用相对路径也可以用绝对路径。若使用相对路径，则这个相对路径是相对于上一个 WORKDIR 的路径，或者是默认根目录 `/`。

```dockerfile
WORKDIR /root
WORKDIR app
WORKDIR src
```
最终的工作路径是`/root/app/src`。

注意事项：
* 若使用相对路径，则是相对于上一个 WORKDIR 的路径，或者是默认根目录 `/`。

## RUN
RUN用于容器内部执行命令（如安装依赖、编译项目等）。
```dockerfile
RUN pip install -r requirements.txt
```

## EXPOSE
用来指定对外开放的端口及协议。
```dockerfile
EXPOSE 80 443
EXPOSE 8080
EXPOSE 8080/tcp
EXPOSE 8080/udp
```

注意事项：
* EXPOSE只会暴露端口，但不会完成宿主机端口到容器端口的映射，需要在镜像**运行**时使用`docker run -p 5000:5000 myapp`完成。  

## ENTRYPOINT
指定容器的固定启动任务，一个Dockerfile只能有一个ENTRYPOINT。配合CMD命令使用。
```dockerfile
ENTRYPOINT ["python"]
```

## CMD
CMD用于指明容器运行任务的默认参数，或作为备用的主命令。
```dockerfile
ENTRYPOINT ["python"]
CMD ["app.py"]
```

注意事项：
* ENTRYPOINT与CMD都只能有一个，如果写了多个只会最后一个生效。

# 使用Dockerfile构建Docker
1. 构造dockerfile
2. 使用build命令打包docker
```bash
docker build -t <镜像名>:<标签> <构建上下文路径>
docker build -t myapp:1.0 .
```
其中参数-t用于给镜像命名。
3. 使用run命令启动容器
```bash
docker run <镜像名> --name <容器名> -d
```
其中-name用于指定容器名，-d表示后台运行。

# 容器是怎么隔离的
容器技术的核心功能，就是通过约束和修改进程的动态表现，从而为其创建一个“边界”。

容器技术里进行隔离的两个核心技术：**Cgroup**技术和**Namespace**技术。

## Cgroup技术
其名源自**控制组群（Control Group）**的简写，是Linux内核的一个功能，通过**追踪和限制**进程组的资源使用情况，来限制、控制与分离一个**进程组**的资源（如CPU、内存、磁盘等）。

## Namespace技术
Namespace是Linux内核的一种机制，通过在内核中为不同进程分配不同的**资源视图**来实现资源隔离。

通俗的来讲，Cgroup负责**资源限制**，限制容器能使用多少资源；Namespace负责**资源隔离**，让容器看不见“外面的世界”。

# Docker的镜像层
Docker镜像实际上不是一个完整的压缩包，而是由一层层镜像层叠加而成的结构，每一层都是一个文件系统的变更记录，最终形成完整的可用镜像。

镜像层由Dockerfile中的**每一条指令**生成，比如：
```dockerfile
FROM ubuntu:20.04        # 创建基础层（Layer 1）
RUN apt-get update       # 创建新的只读层（Layer 2）
RUN apt-get install -y python3 # Layer 3
COPY . /app              # Layer 4
```

镜像层的特点：
* 每执行一条指令，就会生成一层
* 每一层都依赖于上一层
* 每一层都是不可变的，都是**只读层**
* 如果中间的镜像层发生变化，Docker就会重建该层及以上的层。

每一个镜像层本质上是一个文件快照系统（通常是一个.tar压缩包），它记录了该层：
* 添加的文件
* 修改的文件
* 删除的文件

使用镜像层的好处：
1. 分层缓存
Docker构建镜像时，如果某层的指令没变，它就会复用该层，避免重新构建。
2. 高效存储
多个镜像可以共用相同的底层层（比如多个 Python 项目共用 ubuntu 基础层），节省磁盘空间。
3. 快速分发
每一层都可以单独下载和上传，Docker Hub只需要同步变化的部分。

# Docker的容器层
基于镜像构建容器时，就是在最外层增加一个**可写层**供动态编辑。
容器层主要负责：
* 容器运行时的文件写入（如生成日志、缓存文件、应用运行时的临时数据）；
* 用户在容器内修改文件（如 echo hello > file.txt）；
容器停止或删除，可写层会消失。若使用 `docker commit`将容器保存成新的镜像，就会把可写层也转化成镜像层。

注意事项：
* Cgroup和Namespace都属于内核空间，与层无关，由进程加载对应的配置；镜像层、容器层都属于文件系统。

# Docker的四种网络模式
 * host模式
 * container模式
 * none模式
 * bridge模式

## host模式
容器不会有独立的network namespace，而是和宿主机共用network namespace，使用宿主机的IP和端口，但是其他资源如文件系统、进程列表还是和宿主机隔离的。

- 优点：网络性能号
- 缺点：没有网络隔离，可能存在端口冲突

## container模式
指定新创建的容器和一个已有的容器共用一个network namespace。

- 优点：可以实现进程隔离+网络共享
- 缺点：一个容器的网络故障会影响多个容器

## none模式
没有network container，完全禁用网络功能

- 优点：网络安全，不会被攻击
- 缺点：无法访问外部，也无法被外部访问

## bridge模式（默认）
bridge模式是**默认**的网络模式。容器有自己的network namespace，有自己NAT IP地址，通过虚拟网桥docker0与宿主机网络进行连接，由虚拟网桥转发网络请求（类似于NAT私有网络地址转换）。

- 优点：网络隔离性好，各自拥有独立的端口
- 缺点：性能不如host模式（中间经过了一层转发）

