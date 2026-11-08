# GitHub Pages 介绍页

`site/` 是可以直接部署的静态页面，不需要 npm、打包工具或第三方运行时。组织方式参考 TinyEdit：页面源码保存在主分支的 `site/`，发布分支 `gh-pages` 的根目录放置 `site/` 中的文件。

## 更新与预览

在仓库根目录运行：

```sh
python3 scripts/build_site.py
python3 -m http.server 8080 --directory site
```

访问 `http://localhost:8080`。脚本同步 README 截图、应用图标和 GPL 许可证；它不会构建应用，也不会提交或推送。

## 部署

1. 将代码推送到自己的 GitHub 仓库。
2. 创建或更新 `gh-pages` 分支，将 `site/` 的内容放在该分支根目录。可以参考 TinyEdit，用临时 worktree 操作；不要覆盖主分支的应用源码。
3. 在仓库 Settings → Pages 中选择 **Deploy from a branch**，来源为 `gh-pages`、目录为 `/ (root)`。

部署地址为 `https://yanghanqing.github.io/tinycopy/`，下载入口指向 `YangHanqing/tinycopy` 的最新 Release。

页面面向普通用户，不展示源码构建说明。支持中文和英文：首次访问按浏览器语言选择，右上角语言图标在中文与英文间切换并记住选择；首次访问根据浏览器语言自动选择。外观图标依次切换跟随系统、浅色和深色。主图由 OCR、JSON 与翻译三组真实界面截图组成，每 6 秒自动切换，悬停、聚焦、离屏或打开大图时暂停，手动切换后停止自动播放；减少动态效果偏好会默认关闭轮播。

仓库设置在 `index.html` 的 `github-repository` meta 中。主分支保留开发说明，Pages 分支只同步静态页面。
