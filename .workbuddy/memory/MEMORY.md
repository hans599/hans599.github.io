# 项目长期约定 (hans599.github.io.source)

## Hexo NexT 博客
- 文章目录：`source/_posts/<分类>/<YYYYMMDD>-<标题>.md`
- 生成命令：`hexo` 不在 PATH，必须用 `npx hexo g`；clean+生成用 `npx hexo clean && npx hexo g`
- front-matter 约定：`tags`/`categories` 用中文分类名；含公式的文章加 `mathjax: true`
- 分类页需 `type: "categories"`（`source/categories/index.md` 已加）；tags 页同理已加 `type: "tags"`（缺此字段会导致对应页面用默认 page 模板而显示为空）
- 可视化：`mermaid` 已在 `_config.next.yml` 开启（`enable: true`），可在 md 用 ` ```mermaid ` 画依赖图/流程图，浏览器端由 mermaid.min.js 渲染
- 主题：NexT 8.27.0
