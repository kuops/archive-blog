#/bin/bash

git_commit_msg="$(date +%F) deploy website "

# git push to github https://github.com/kuops/blog-source-code.git
git add -A
git commit -m "$git_commit_msg"
git push origin master

# hexo deploy to static website
npm install
hexo clean
hexo generate -d
