# RebootTools Shortcuts 修改说明

基于上传的 RebootTools-main 源码修改。

## 修改内容

- `Resources/Info.plist`：注册 `reboottools://` URL Scheme。
- `AppDelegate.swift`：处理 `reboottools://reboot`，兼容冷启动和 App 已运行两种情况；校验 scheme/host/path；避免同一进程重复触发。
- URL 请求复用原项目已有的 `DeviceController.rebootDevice()`，不复制或替换 `RebootRootHelper`。
- `Makefile`：修正原先硬编码大小写的 IPA 改名逻辑，兼容 control 文件中的小写包标识符。
- `Shortcut/README.md`：提供 iOS 14.4 快捷指令动作配置。
- `scripts/build.sh`：提供 macOS + Theos 构建脚本。

## 尚未完成的验证

本次运行环境不是 macOS，且没有 Xcode / Theos，因此没有生成或验证可安装 IPA。必须在 macOS + Theos 环境编译，并在 iPhone SE 2 / iOS 14.4 / TrollStore 实机测试后才能确认最终可用。

## 安全提示

URL Scheme 不具备调用方身份认证。任何本机 App 或快捷指令只要知道该 Scheme，就可能请求重启设备。不要把 `reboottools://reboot` 放到不可信网页或自动化入口。
- `RootViewController.swift`：当 App 由重启 URL 冷启动时，跳过原项目“打开 App 自动执行动作”设置，避免重复执行或弹出原有确认框。
