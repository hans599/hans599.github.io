# 每次写作前
git pull origin source

# 写文章...

# 提交更改
git add .
git commit -m "更新内容"
git push origin source

# 部署（不用切换分支）
npx hexo clean && npx hexo deploy

# 如果报错 cannot find module 'hexo'  
# 那么先 npm install

