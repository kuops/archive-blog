# blog-source-code

# 下载 Blog 源代码

克隆 Blog 源代码

```
git clone git@github.com:kuops/blog-source-code.git
```

# 创建文章

你可以执行下列命令来创建一篇新文章。


```
hexo new post <post-title>
```

# 分类和标签

只有文章支持分类和标签，您可以在 Front-matter 中设置。

Front-matter 是文件最上方以 --- 分隔的区域，用于指定个别文件的变量。

```
categories:
- Diary
tags:
- PS3
- Games
```
# 本地测试

本地安装 nodejs 和 hexo 之后运行如下命令

```
npm install
hexo s -i <ipaddress>
```
# Travis CI 持续部署

需要使用 Travis-cli 命令进行推送私钥，然后把公钥添加到 github

```
gem install travis
travis login
travis encrypt-file /root/.ssh/id_rsa  --add
```
travis encrypt 生成的文件多了一个转义符号,删除之

```
before_install:
- openssl aes-256-cbc -K $encrypted_5bc884c9e074_key -iv $encrypted_5bc884c9e074_iv
  -in id_rsa.enc -out ~/.ssh/id_rsa -d
```
