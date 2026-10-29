# Clients

这个目录存放随 App 打包的「网页版 Minecraft 客户端」。

**仓库里不放这些二进制文件**（Minecraft 衍生资源、体积大），构建时由 Tools/fetch_clients.sh 按固定 URL + sha256 现拉。

每个版本一个子目录，入口文件名必须是 index.html，可放 version.json 自定义标题/排序。
