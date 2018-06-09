# blog-source-code [![Build Status](https://travis-ci.org/kuops/blog-source-code.svg?branch=master)](https://travis-ci.org/kuops/blog-source-code)

# 下载 Blog 源代码

克隆 Blog 源代码

```
git clone git@github.com:kuops/blog-source-code.git
```

# 创建文章

你可以执行下列命令来创建一篇新文章。


```
./deploy.sh  new article-name
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
travis encrypt 生成的 .travis.yml 有些问题,按如下设置

```
mkdir  -p .travis
mv id_rsa.enc .travis/

before_install:
- openssl aes-256-cbc -K $encrypted_5bc884c9e074_key -iv $encrypted_5bc884c9e074_iv
  -in .travis/id_rsa.enc -out ~/.ssh/id_rsa -d
- chmod 600 ~/.ssh/id_rsa
- eval $(ssh-agent)
- ssh-add ~/.ssh/id_rsa
- git config --global user.name "kuops"
- git config --global user.email opshsy@gmail.com
```

# https

使用免费的 Cloudflare 网站注册的 https , 并设置强制跳转，具体参考如下博客
```
https://molunerfinn.com/hexo-travisci-https/
```
