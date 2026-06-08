---
title: kubectl命令使用
date: 2025-08-04 13:26:29
tags: 
    - kubectl
    - k8s
categories:
    - 基础知识
---

由浅入深介绍kubectl命令的使用，常用于服务器上的运维操作。
<!-- more -->

kubectl是k8s的命令行客户端，用于管理集群中各种资源。其中kubectl命令可以简写成 k。
K8s 资源对象也有简写（大小写不敏感）：
| 全称                    | 简写     |
| --------------------- | ------ |
| pods                  | po     |
| services              | svc    |
| namespaces            | ns     |
| nodes                 | no     |
| deployments           | deploy |
| replicasets           | rs     |
| daemonsets            | ds     |
| statefulsets          | sts    |
| configmaps            | cm     |
| secrets               | secret |
| persistentvolume      | pv     |
| persistentvolumeclaim | pvc    |
| endpoints             | ep     |
| jobs                  | job    |
| cronjobs              | cj     |
| events                | ev     |

```bash
k get po -n kube-system      # 查看 kube-system 命名空间下的所有 Pod
k describe deploy myapp      # 查看 myapp Deployment 详情
```

# 查看资源信息
```bash
kubectl get pods              # 查看当前命名空间的所有 Pod
kubectl get pods -n kube-system  # 查看指定命名空间的 Pod
kubectl get svc               # 查看 Service
kubectl get nodes             # 查看集群节点
kubectl get deployments       # 查看 Deployment
kubectl get ns                # 查看所有命名空间
kubectl get pod <pod-name> -o wide  # 显示更多信息（IP、节点等）
kubectl api-resources       # 查看当前集群支持的资源类型
```

若查看指定资源的yaml信息，可用
```bash
kubectl get <资源类型> <资源名称> -o yaml

kubectl get pod my-pod -o yaml
kubectl get pods -o yaml
kubectl get deployment my-deploy -o yaml
kubectl get deploy my-deploy -o yaml > my-deploy.yaml
```

在 kubectl 里，-o 是 --output 的简写，用来指定输出的格式。

| 格式               | 用法示例                                                       | 说明                         |
| ---------------- | ---------------------------------------------------------- | -------------------------- |
| **wide**         | `kubectl get pods -o wide`                                 | 在表格模式下显示更多信息（节点名、IP 等）     |
| **yaml**         | `kubectl get pod my-pod -o yaml`                           | 以 YAML 格式输出资源完整描述（适合阅读、导出） |
| **json**         | `kubectl get pod my-pod -o json`                           | 以 JSON 格式输出资源完整描述（适合脚本处理）  |
| **name**         | `kubectl get pods -o name`                                 | 只输出资源名称（便于脚本批量处理）          |
| **jsonpath=...** | `kubectl get pods -o jsonpath='{.items[*].metadata.name}'` | 用 JSONPath 表达式提取指定字段       |
| **go-template**  | `kubectl get pods -o go-template='{{.metadata.name}}'`     | 使用 Go 模板格式化输出（高级用法）        |

# 修改yaml
可用通过`edit`命令修改deployment的yaml字段，修改image镜像的方式来实现黑屏变更。

```yaml
kubectl -n kox edit cafedeployment cd-name
```

# 发布
k8s中使用rollout控制Deployment的发布过程，指明先缩后扩、先扩后缩。
rollout通过读取yaml中的**partition**字段来实现分组发布，达到渐进式更新的效果。

在云原生中，`partition=n`表示Deployment中n个pod保持旧镜像不变，其余的pod进行更新。通过逐步缩小partition的值使其最终等于0，以此来达到分批发布的效果

在蚂蚁集团的cafedeployment中（控制应用的crd）刚好相反，`partition=n`表示选取 n 个pod进行更新，每次发布前会有一个webhook将partition重置为0，触发分组发布，逐步将partition的值更新为最大pod数。若webhoos失效，会导致partition经过上一次发布后置为最大pod数，导致发布一把梭。
同时在蚂蚁集团中，rollout不再是一种发布机制，而是一种crd，用于控制实际发布的运行。


