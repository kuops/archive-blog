#/bin/bash

git_commit_msg="$(date +%F) deploy website "

# git push to github https://github.com/kuops/blog-source-code.git
git config --global user.name "kuops"
git config --global user.email opshsy@gmail.com
git add -A
git commit -m "$git_commit_msg"
git push origin master

# hexo deploy to static website
#npm --registry http://npmreg.proxy.ustclug.org install
#hexo clean
#hexo generate -d
