# GitHub Actions 云端编译指南

本项目已加入 `.github/workflows/build.yml`。工作流会在 GitHub Actions 的 macOS 14 runner 上安装 Theos、检查源码和 Helper、构建 IPA，并验证最终 app bundle 内确实包含两个可执行 Helper。

## 上传到 GitHub

1. 在 GitHub 新建一个空仓库，例如 `RebootTools-Shortcuts`。
2. 解压本项目 ZIP，将里面的全部文件（包括隐藏目录 `.github`）上传到仓库根目录；或使用 Git：

   ```bash
   git init
   git add .
   git commit -m "Add RebootTools Shortcuts build"
   git branch -M main
   git remote add origin https://github.com/你的用户名/RebootTools-Shortcuts.git
   git push -u origin main
   ```

3. 打开仓库的 **Actions** 页面，选择 **Build RebootTools Shortcuts**。
4. 首次运行若 GitHub 提示启用 Actions，选择允许。
5. 等待任务完成。绿色勾表示构建和包结构检查通过；展开 **Upload build artifact** 后，在该次运行页面底部的 **Artifacts** 下载 `RebootTools-Shortcuts-TrollStore`。
6. 解压下载的 artifact，得到 `RebootTools-Shortcuts.tipa`。通过 TrollStore 安装。

## 手动触发

仓库 **Actions → Build RebootTools Shortcuts → Run workflow → Run workflow**。

## 快捷指令设置

在 iOS「快捷指令」中新建快捷指令，添加「打开 URL」动作，URL 填：

```text
reboottools://reboot
```

保存后点击该快捷指令即可请求设备重启。无需在快捷指令里额外添加「打开 App」动作。

## 重要说明

- 本工作流只负责编译和包结构检查。没有在真实 iPhone SE 2 / iOS 14.4 上安装、验证权限和执行重启，因此不能把 CI 绿色勾当成设备重启已验证。
- URL Scheme 无二次确认意味着任何能够让系统打开 `reboottools://reboot` 的其他 App、网页或自动化，都可能触发重启。不要把该 Scheme 暴露给不可信来源。
- 构建使用项目随附的预编译 `RebootRootHelper` 和 `RebootUserSpaceHelper`。工作流会检查它们存在、可执行且包含 arm64；不会从 helper 子目录重新编译这两个二进制。
- GitHub Actions 的 Theos setup action 文档注明目前使用 macOS runner；Theos 官方变量文档说明 `XXX_RESOURCE_DIRS` 会把 Resources 目录内容复制进 app bundle。本项目显式设置该变量，避免 helper 没有进入 `.app` 的问题。
