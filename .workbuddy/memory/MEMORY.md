# 项目长期约定 (hans599.github.io.source)

## Hexo NexT 博客
- 文章目录：`source/_posts/<分类>/<YYYYMMDD>-<标题>.md`
- 生成命令：`hexo` 不在 PATH，必须用 `npx hexo g`；clean+生成用 `npx hexo clean && npx hexo g`
- front-matter 约定：`tags`/`categories` 用中文分类名；含公式的文章加 `mathjax: true`
- 分类页需 `type: "categories"`（`source/categories/index.md` 已加）；tags 页同理已加 `type: "tags"`（缺此字段会导致对应页面用默认 page 模板而显示为空）
- 可视化：`mermaid` 已在 `_config.next.yml` 开启（`enable: true`），可在 md 用 ` ```mermaid ` 画依赖图/流程图，浏览器端由 mermaid.min.js 渲染
- 主题：NexT 8.27.0
- **标题不要手加序号**：不要写 `一、二、三` 这类中文序号，也不要 `2.1 / 2.2` 这类手动编号——Hexo/NexT 渲染时会自动给标题编号，手加会导致双重编号。直接写标题内容即可（如 `# 环境搭建`、`## Windows：...`）。
- **不要帮我部署/发布**：每次改完博客只直接编辑 md 源文件即可，部署与发布由用户自己手动完成。不要执行 `hexo deploy`，也不要代为跑发布流程；`hexo g` 生成也交给用户自己处理。
- **本地预览坑**：本 workspace 的 `node_modules` 缺 `hexo-generator-post`，导致 `npx hexo g` 报 "No posts"、public/ 下不产生任何文章 HTML（仅框架静态资源）。`hexo list post` 也返回空。需 `npm i hexo-generator-post` 后才能本地渲染文章；部署环境通常已具备，不影响线上构建。
- 文章内可用 ASCII 方框图 + mermaid 双图示表达流程/结构（如 FFmpeg 文章的容器结构图与解复用→解码→编码→封装流水线图）
