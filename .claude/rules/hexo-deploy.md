# Hexo 博客部署规则

## 项目信息

- 博客框架：Hexo
- 主题：Fluid
- 部署方式：hexo-deployer-git → GitHub Pages
- 远端仓库：xiaopengqiu/xiaopengqiu.github.io (branch: main)
- 本项目不是 git 仓库，无需 git 操作

## 文章创建规则

- 文章路径：`source/_posts/{year}/{month}/{filename}.md`
- year/month 基于文章 date 字段，目录不存在时需先创建
- frontmatter 格式：
  ```yaml
  ---
  title: {标题}
  date: {YYYY-MM-DD HH:mm:ss}
  tags:
    - {标签1}
    - {标签2}
  categories:
    - {分类}
  ---
  ```
- 使用 `<!-- more -->` 分隔摘要与正文

## 部署流程

当用户要求推送/部署/发布博客时，按顺序执行以下三步，不可跳过：

1. `npm run clean` — 清理缓存和生成的文件
2. `npm run build` — 生成静态文件（等同于 hexo generate）
3. `npm run deploy` — 部署到 GitHub Pages（等同于 hexo deploy）

所有命令在项目根目录 `e:/技术学习/blog/hexo-blog` 下执行。

## 注意事项

- 部署前必须先 clean 再 build，避免旧缓存导致内容不更新
- build 时出现的 `LF will be replaced by CRLF` 警告可忽略，不影响部署
- 部署完成后告知用户稍等片刻 GitHub Pages 即可生效
- 不要对本项目执行 git init 或 git 操作，部署由 hexo-deployer-git 内部处理
