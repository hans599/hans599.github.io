# # 更换电脑
# # 克隆source分支到本地
# git clone -b source https://github.com/hans599/hans599.github.io.git 

# # 进入项目目录
# cd hans599.github.io

# # 安装依赖
# npm install

# # 安装next主题
# git clone https://github.com/next-theme/hexo-theme-next themes/next

# # 将其配置文件拷贝到自己的项目中  如果已经有了 就不需要了
# cp _config.next.yml themes/next/_config.yml


# # ----------------------------------------------------------------------------------  #

# # 每次写作前
# git pull origin source

# ----------------------------------------------------------------------------------  #

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

