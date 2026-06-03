# 更换电脑
# 克隆source分支到本地
git clone -b source https://github.com/hans599/hans599.github.io.git 

# 进入项目目录
cd hans599.github.io

# 安装依赖
npm install


# ----------------------------------------------------------------------------------  #

# 每次写作前
git pull origin source

# 写文章...

# 提交更改
git add .
git commit -m "更新内容"
git push origin source

# 部署（不用切换分支）
npx hexo clean && npx hexo generate && npx hexo deploy 

# 本体调试渲染
npx hexo server
# 如果报错 cannot find module 'hexo'  
# 那么先 npm install

