# Paster

Paster 是一款本机运行的 macOS 剪贴板和截图工具。它常驻菜单栏，记录文字、链接和图片，提供搜索、固定、再次复制、可选自动粘贴，以及区域截图、滚动截图和桌面贴图。首次启动时剪贴板记录默认关闭，由用户自行开启。

安装包请从 [GitHub Releases](https://github.com/zhych0111/paster/releases/latest) 下载。当前预览版仅支持 Apple 芯片 Mac，最低要求 macOS 13。

## 环境与运行

- macOS 13 或更新版本
- Apple Swift 6 工具链；当前版本可用 Command Line Tools 构建本机试用包

```bash
swift build
swift run PasterSelfTests
swift run Paster --self-test
./scripts/build-app.sh
open dist/Paster.app
```

`dist/Paster.app` 是试用包，尚未经过 Apple Developer ID 签名或 Apple 公证。配置本机开发证书后，构建使用固定证书签名；未配置时使用临时签名。首次运行后可在菜单栏点击剪贴板图标，也可使用默认快捷键 `⌃⌥V` 打开历史。快捷键冲突时仍可从菜单栏打开，并可在设置中改用另一个组合。

### 截图与贴图（当前源码构建版）

- 菜单栏选择“区域截图并贴图”，或用默认快捷键 `⌃B`；在设置中可更换键位。选区完成后，图片浮在普通窗口上方。贴图工具栏可关闭、复制或保存 PNG，右下角可缩放；长图可在贴图内滚动。
- 菜单栏选择“滚动截图”，框出同一显示器上的滚动内容，松开鼠标开始。Paster 优先自动向下滚动；检测到用户滚轮、触控板、鼠标拖动或键盘操作后，立即切成手动模式，本次截图不再恢复自动。可从菜单栏或选区外的小面板点“停止并预览”，然后选择贴图、复制或保存。
- 滚动截图需要“屏幕录制”权限。自动滚动和输入接管还需要系统允许辅助功能及输入观察；这些权限不可用时，截图仍可在手动滚动模式下进行。首次允许屏幕录制后若仍无法取帧，请重启 Paster 再试。
- 为避免错误拼接，画面重叠不可靠时会停止并保留可用部分。单张图片最多 2500 万像素；滚动截图最多采样 60 段或运行 120 秒。不同应用的滚动实现不一，自动滚动与拼接效果需要在目标应用中实测。

**当前 GitHub Release 的 v0.1.0 DMG 是旧版快照，尚不包含上述截图功能。** 本节适用于从当前源码构建的 0.2.2 开发版应用。

### 在另一台 Mac 上试用

当前 `dist/Paster-0.1.0-macos-arm64.dmg` 适用于 Apple 芯片 Mac，要求 macOS 13 或更新版本。将 DMG 复制到目标电脑，在 Finder 中双击挂载，再把 `Paster.app` 拖到镜像中的 `Applications` 快捷入口；随后从“应用程序”文件夹双击打开，并推出磁盘镜像。它是菜单栏应用，启动后在屏幕顶部显示剪贴板图标，不会出现在 Dock 中。也可以传输 `dist/Paster-0.1.0-macos-arm64.zip`，解压后把应用拖入“应用程序”文件夹。

此试用包只有临时签名，未经过 Apple 公证。若 macOS 阻止首次打开，在“系统设置 → 隐私与安全性”中找到刚才被阻止的 Paster，点击“仍要打开”。仅对自己确认来源的试用包这样操作。自动粘贴功能需要在目标电脑上单独授予“辅助功能”权限；普通复制和搜索不需要该权限。

如果重新构建，可用 `ditto -c -k --keepParent dist/Paster.app dist/Paster-0.1.0-macos-arm64.zip` 重新生成 ZIP；现有 DMG 是当前版本的快照，重新构建后也需要重新制作。Intel Mac 不能运行当前仅含 `arm64` 的程序，需要单独构建 `x86_64` 或通用版本。

## 使用与数据

- 记录在首次启动时关闭。启用后，应用每约 500 毫秒检查一次剪贴板变化；启动前或暂停期间的内容不会补录。
- 首版支持纯文本、HTTP(S) 链接和位图。富文本只保留可读的纯文本表示；文件对象、OCR 和跨设备同步尚未实现。单项上限为 20 MiB。
- 未固定内容默认保留 30 天，最多 1000 项；固定内容需要手动删除。设置中可修改保留期限、排除应用 Bundle ID、暂停记录或清空所有历史。
- 历史数据库和图片位于 `~/Library/Application Support/Paster/`。应用不上传剪贴板内容，也没有分析 SDK；当前版本未提供应用层加密。排除应用依据检查时的前台应用判断，快速切换应用时可能不准确。
- 选择“复制”始终将历史项写回系统剪贴板。自动粘贴默认关闭；启用后可在设置页主动请求 macOS 辅助功能授权。权限不足或目标应用不可用时，内容仍会留在剪贴板，供用户手动粘贴。

## 开发说明

源代码由 Swift Package Manager 管理。`PasterCore` 保存数据模型、捕获策略和 SQLite 历史；`Paster` 包含 macOS 菜单栏界面和系统剪贴板接入。此机器的 Command Line Tools 不提供 `XCTest` 或 Swift Testing，因此目前使用 `PasterSelfTests` 和 `Paster --self-test` 进行自动自检。将来配置完整 Xcode 后，可将这些检查迁移到标准测试目标。

应用图标源文件是 `Resources/PasterLogo.png`，打包使用 `Resources/Paster.icns`。

`swift run Paster --window-self-test` 会短暂显示测试窗口并切换到 Finder，通过 WindowServer 检查贴图在应用失去焦点后仍留在屏幕上。普通 `--self-test` 不执行这项桌面交互测试。

### 本机开发签名与录屏授权

临时签名以每次构建的代码哈希标识程序。重编译后，macOS 可能仍显示旧的录屏权限开关，却拒绝新程序。可为本机开发创建固定签名证书：

```bash
python3 scripts/setup-local-signing.py --trust-code-signing
./scripts/build-app.sh
```

第一条命令创建项目专用的本机证书和钥匙串，并在当前用户的信任设置中只启用该证书的代码签名政策，不启用 TLS 网络证书信任。私钥、钥匙串和本机配置位于被 Git 忽略的 `.local/signing/`，不得上传或共享；构建结束后恢复原来的钥匙串搜索列表。它用于本机开发，不等同于 Apple Developer ID 或公证。也可通过 `PASTER_SIGN_IDENTITY` 指定已有的开发者签名身份。

`python3 scripts/verify-signing.py` 会签署一个内容已变化的临时副本，并检查它仍满足原构建的签名身份要求；不会覆盖当前应用。

首次从临时签名切到固定证书时，需要在系统设置里移除旧 Paster 录屏条目，重新添加当前 `.app` 并授予权限，再退出并重开。之后保留同一证书，更新版本即可满足同一身份要求。[Apple 对签名身份与隐私授权的说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

从实际 `.app` 运行 `--capture-self-test --diagnostic-output <本机JSON路径>` 可检查 ScreenCaptureKit 和系统截图两条路径是否收到小尺寸图片。检查只保留结果、错误代码和图片尺寸，临时图片立即删除。

功能规格、技术设计和任务清单位于 `openspec/changes/macos-clipboard-manager/`。

## 许可证

本项目采用 [MIT License](LICENSE)。
