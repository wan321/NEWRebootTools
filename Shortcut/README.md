# 用快捷指令触发 RebootTools（iOS 14.4+）

本项目注册的 URL Scheme 与三种动作（与 App 内三个按钮一一对应）：

| URL | 动作 | 实际行为 | 屏幕表现 |
|---|---|---|---|
| `reboottools://reboot` | 重启设备 | `RebootRootHelper` → `reboot(0)` | Apple 开机 logo，整机断电重启 |
| `reboottools://userspace` | 用户空间重启 | `RebootUserSpaceHelper` → launchd userspace-reboot | 短暂黑屏后回到锁屏 |
| `reboottools://respring` | 注销 | `killall SpringBoard` | 一瞬间回到桌面 |

在 iPhone 上：

1. 先通过 TrollStore 安装编译后的 RebootTools Shortcuts TIPA。
2. 打开「快捷指令」并新建快捷指令，例如命名为「立即重启」。
3. 添加「URL」动作，内容按需填写上表中的一个 URL。
4. 添加「打开 URL」动作，并确保它打开上一步的 URL。
5. 可将快捷指令添加到主屏幕或锁屏小组件。

## 已知限制

- **锁屏不能运行**：设备锁定时 iOS 不允许「打开 URL」把 App 拉到前台；而 App 自身也只在 `applicationDidBecomeActive` 时才真正执行重启，后台收到 URL 只会挂起等待。因此锁屏自动化实际要等到解锁后才会执行。
- **需要 App 在前台**：三种动作都由主 App 触发，没有常驻服务。
- **失败可见**：Helper 启动失败（常见于缺少 `platform-application` / reboot 权限）现在会弹窗提示，同时写入 `Documents/reboottools-url.log`，可用 TrollStore 的文件浏览器或 Filza 查看。

## 安全提示

自定义 URL Scheme 不是访问控制机制；任何能够调用该 Scheme 的本地 App 或自动化都可能触发重启。请勿在不可信网页或自动化中公开使用。
