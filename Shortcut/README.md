# 创建「立即重启」快捷指令（iOS 14.4）

本项目注册的 URL Scheme：

```text
reboottools://reboot
```

在 iPhone 上：

1. 先通过 TrollStore 安装编译后的 RebootTools Shortcuts TIPA。
2. 打开「快捷指令」并新建快捷指令，命名为「立即重启」。
3. 添加「URL」动作，内容填写 `reboottools://reboot`。
4. 添加「打开 URL」动作，并确保它打开上一步的 URL。
5. 可将快捷指令添加到主屏幕。

运行时会启动 RebootTools，并由主 App 调用原项目的 `DeviceController.rebootDevice()` / `RebootRootHelper` 执行系统重启。

注意：这里提供的是准确的动作配置，不是伪造的 `.shortcut` 导入文件。自定义 URL Scheme 不是访问控制机制；任何能够调用该 Scheme 的本地 App 或自动化都可能触发重启。请勿在不可信网页或自动化中公开使用。
