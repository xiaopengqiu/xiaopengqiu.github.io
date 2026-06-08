---
title: k8s相关概念介绍
date: 2025-06-11 22:49:11
tags:
    - k8s
categories:
    - 技术介绍
---

k8s负责多个pod的部署与运维，由一系列**Pod**以及管理Pod的一系列**工具**组成。
<!-- more -->

# 什么是Pod
Pod是k8s中最小的可部署单元，一个Pod中包含多个容器，这些容器共享namespace、volume、声明周期，通常用于部署一个功能单元。

将一个功能切分成多个子功能部署到不同的容器中，这种模式叫做sidecar，Pod中的多个容器协同工作共同组成一个功能单元。

## Pod控制器
为了确保Pod的状态始终符合预期，定义了 Pod控制器。Pod控制器中定义了Pod的副本数、生命周期、健康状态检查等等，用于安全稳定地创建、管理、维护Pod。

**在云原生应用中，一般不会直接去创建裸的Pod，而是通过Pod控制器去创建Pod，确保Pod生命周期地安全、稳定**。

Pod控制器主要包括五大类：
1. Deploymoent。用于管理一组无状态的Pod，这一组Pod通常是一个Pod的多个副本。这些Pod是无状态的，可以无序启动和关闭，系统会尽量保证副本数量，但没有顺序要求。这些Pod的IP和DNS是动态的，重启后会发生变化。
2. Stateful。用于管理一组有状态的Pod，这些Pod通常是一个Pod的多个副本，但这些副本之间定义了启动顺序，列入：数据库、消息队列。这些Pod的IP和DNS是固定的，重启后不会发生变化。
3. DemonSet。用于确保集群中每个服务器都会有一个Pod副本。
4. Job。用于管理一次性Pod，执行完后销毁。其副本数量相当于指明任务运行的次数。多用于脚本的管理。
5. CronJob。用于控制定时运行的Job。

## Namespace
为了隔离不同类型的资源组，引入了命名空间（namespace）的概念。namespace可以理解为k8s内部的虚拟集群组，查询k8s内的资源需要指定namespace。

不同名称空间内的“资源”名称可以相同，相同名称空间内的同种“资源”、“名称”不能相同。

## Label
对于k8s中众多的资源，使用Label机制进行分类管理，Label由多个key-value键值对组成。

一个标签可以对应多个资源，一个资源也可以对应多个标签，他们是多对多的关系。

一个资源可以通过多个标签实现不同维度的管理。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-nginx
  labels:
    app: nginx
    tier: frontend
```
例如：控制器（如 Deployment）不会直接绑定某个 Pod，而是根据标签选择 Pod。

工作流程示意：

1. 创建一个 Deployment，指定了 matchLabels: app=nginx。

2. Deployment 控制器通过标签找到当前所有 app=nginx 的 Pod。

3. 根据期望副本数（replicas）对这些 Pod 进行增删改。

标签最常用在Pod上，用于对Pod进行筛选，同时对于k8s中的其他资源，也可以用标签进行描述。

给资源打上标签后，可以使用标签选择器过滤指定的标签。
标签选择器目前有两个：基于等值关系（等于、不等于）和基于集合关系（属于、不属于、存在）。许多资源支持内嵌标签选择器字段
* matchLabels
* matchExpressions

## Service
k8s中Pod本身的IP地址不是固定的，随着Pod的销毁和重建，其**IP就会发生变化**。
为了给Pod提供稳定的对外IP入口，引入了Service。

Service可以看作“网关”，对外提供稳定访问的虚拟IP+DNS名称，接收请求后路由转发至对应的Pod进行服务。转发的过程是通过**Label Selector**筛选到对应的Pod，避开了动态IP。

Pod控制器stateful也是通过service为Pod提供稳定的IP，确保Pod每次重建都会保留固定的IP和DNS。

Service共有5种类型：
* ClusterIP（默认类型），用于集群内部通信，会自动分配一个固定的虚拟 IP，该IP不能从集群外访问，适用于服务之间的内部通信。
* NodePort，通过端暴露端口的方式可用于集群外访问的Service，给每个Node暴露一个端口，可通过**NodeIP：NodePort**进行访问。注意：Node是Cluster中的最小计算单元，一般是一个实际运行的机器，上面包含多个Pod。
* LoadBalancer，在NodePort的基础上增加了一层负载均衡器，用于创建可负载均衡的对外访问的Service。
* ExternalName，用于在集群内部访问外部服务，将集群内部主机名映射到外部服务的DNS稳定访问。
* Headless Service，通常用于StatefulSet，不分配Cluster IP，直接暴露每个Pod的真实IP，然后通过DNS每次都指向该Pod，提供稳定的主机名访问，即IP不固定，但DNS主机名稳定。

## Ingress
Ingress负责管理集群HTTP/HTTPS路由规则的资源。与Service相比，Service侧重于IP+Port进行请求转发（TCP/UDP），Ingress通过域名URL+Path进行请求转发（HTTP/HTTPS）。

Ingress定义了路由规则，但不会自动生效，由Ingress Controller监听 Ingress 对象，由Ingress Controller根据Ingress定义的规则进行实际生效、执行路由转发。Ingress Controller会将请求转发给对应的Service，再由Service转发给对应的Pod进行执行。

## k8s整体架构

k8s的整体架构图如下所示：

{% asset_img k8s结构图.jpeg k8s架构图 %}

下面根据外部请求打到k8s的整个路由过程，详细介绍一下k8s的整体架构及各个组件的作用：

* 外部请求访问k8s服务时，请求优先打到Ingress Controller，根据Ingress定义的规则路由给对应的Service。
* Kube-proxy：Kube-proxy是运行在每个Node上的网络代理组件，由该组件实现Service到Pod的路由转发及负载均衡，为Service提供cluster内部的服务发现和负载均衡。
* kubelet: 运行在每个节点上，启动并管理的容器最终处理请求（拉取镜像、挂载卷、调用容器运行时，启动容器）。Pod控制器就是通过kubelet实现对Pod的控制（Pod控制器定义规则PodSpec并写入etcd，由kube-scheduler分配给具体的节点，在节点上由kubelet负责最终执行）。
* etcd：是一个分布式的、高可用的键值数据库，采用 Raft 一致性算法 保证数据一致性，用于存储k8s中资源对象的配置和状态。
* kube-scheduler：负责调度决策，负责将Pod调度给指定的节点，	为集群中新建的、尚未分配节点的 Pod 选择最合适的节点。
* api server：k8s的控制中枢，提供restful api接口的方式，调度k8s各个组件的协作与执行，也是唯一一个可以读写etcd的组件。
* kubectl：是k8s官方提供的命令行工具，它发送http请求给api server，完成k8s的一系列管理运维操作。
* Controller Manager: 负责管理各个资源类型的生命周期，包括Ingress Controller、ReplicaSet Controller、Deployment Controller、Service Controller等等，每种资源类型都会有对应的控制器。
