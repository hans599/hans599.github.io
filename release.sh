# 每次写作前
git pull origin source

# 写文章...

# 提交更改
git add .
git commit -m "更新内容"
git push origin source

# 部署（不用切换分支）
hexo clean && hexo deploy