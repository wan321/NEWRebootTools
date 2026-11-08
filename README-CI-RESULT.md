# 本次 CI 修正摘要

- 将 `RebootTools_RESOURCE_DIRS` 设置为 `Resources`，使两个 helper、Info.plist 和 LaunchScreen 资源进入 app bundle。
- 移除原 Makefile 中依赖固定大小写包名的重命名命令，避免包名不匹配导致误判。
- 调整 AppDelegate：在创建 RootViewController 之前识别冷启动 URL Scheme，避免普通启动动作先于 URL 标记执行。
- 增加源文件校验、构建产物校验和 GitHub Actions 工作流。

这是一份可提交到 GitHub 运行的 CI 工程包，不是已经成功编译的 IPA。当前执行环境不是 macOS，无法在这里运行 Theos/Xcode 构建。
