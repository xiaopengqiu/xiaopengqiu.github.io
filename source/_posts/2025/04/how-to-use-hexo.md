---
title: hexo常用命令
date: 2025-04-19 23:09:33
tags: 
    - hexo
categories:
    - 技术介绍
---

介绍一下hexo使用过程中常用的指令。

<!-- more --> 

# 如何使用hexo

## 创建文章

1. 在默认目录source/_post下创建文章。
```bash
hexo new post <article name>
```

2. 在子目录下创建文章，使用-p参数，会在source/_post下创建子目录dir。
```bash
hexo new post -p <dir/article name>
```

## 创建草稿

1. 默认会在source/_drafts目录下创建草稿。
```bash
hexo new draft <draft name>
```

## 发布草稿
1. 直接将草稿中的文件移动到默认目录source/_post下
```bash
hexo publish <draft name>
```

## 设置摘要
在摘要内容末尾添加标注`<!-- more -->`，会将该标志前面部分设置为摘要，后面的为正文。

## 插入图片
需要把图片先存入文章的同名目录下，并使用asset_img命令在文章指定位置插入图片。
```txt
{% asset_img 图片名称 图片标题 %}
```

## hexo部署

1. 在config文件中配置将hexo部署到github上，配置方法参考[文章](https://blog.csdn.net/yaorongke/article/details/119089190)。
2. 使用命令`hexo g -d`完成文章内容推送到GitHub上。g表示generate生成网页内容，d表示deploy部署，上述命令可以写成`hexo generate && hexo deploy`


