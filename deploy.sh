#/bin/bash

git_commit_msg="$(date +%F) deploy website "

npm_install(){
    if ! [ -d node_modules ];then
        docker run -v $PWD:/app  kuops/hexo:latest  npm install
    fi
}

new(){
    if [ $# -ne 2 ];then
        echo "Usage: $0 new aticle-name"
        exit 23
    fi
    docker run -v $PWD/$BLOG_DIR_NAME:/app  kuops/hexo:latest  hexo new $2
}

push(){
    # git push to github https://github.com/kuops/blog-source-code.git
    git config --global user.name "kuops"
    git config --global user.email opshsy@gmail.com
    git add -A
    git commit -m "$git_commit_msg"
    git push origin master
}


case $1 in
    new)
        npm_install
        new  $1 $2;;
    push)
        push;;
    *)
        echo "Usage: $0 {deploy|new}  [article-name]"
esac
