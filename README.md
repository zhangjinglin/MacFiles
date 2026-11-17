# MyFiles

macOS 原生双栏文件管理器。左侧显示已挂载的磁盘和可逐层展开的目录树，右侧显示当前目录的直接子项，双击或 Enter 打开。

## 构建与运行

要求：macOS 14 或更高版本，已安装 Xcode Command Line Tools（提供 `swift`）。

```bash
./build.sh
open build/MyFiles.app
```

`build.sh` 会执行 `swift build -c release`，组装 `build/MyFiles.app`（Info.plist + ad-hoc 签名）。项目没有第三方依赖，未启用 App Sandbox。

## 功能

- 左侧：通过 `FileManager.mountedVolumeURLs` 枚举已挂载卷，按本机磁盘、外接磁盘、网络磁盘分组，卷名使用系统卷名称。
- 左侧目录树使用 `NSOutlineView`，只在用户展开目录时读取下一级子目录，只显示目录，过滤隐藏文件和隐藏目录。
- 右侧文件列表使用 `NSTableView`，显示系统图标和文件名，按 `localizedStandardCompare` 自然升序排列（`file2` 在 `file10` 之前）。
- 双击文件夹进入，双击文件调用 `NSWorkspace.open` 使用系统默认应用打开。
- 右侧列表按 Enter 执行打开（不是重命名），上下方向键切换选中项。
- 右键点击列表项弹出“删除”菜单，也可按 Cmd+Delete。删除前总会弹出确认框：本机和外接磁盘移入废纸篓，网络磁盘永久删除（提示不可恢复）。
- 左侧目录树选中目录后按 Enter 展开或折叠，与双击箭头行为一致。
- Tab / Shift+Tab 在左侧目录树和右侧文件列表之间切换键盘焦点，左右方向键保持原生语义（展开/折叠目录），互不冲突。
- 所有目录读取和卷枚举都在后台线程执行，结果回到主线程更新 UI。
- 目录读取失败（无权限、卷已卸载、网络中断等）时在右侧显示错误提示，不崩溃。
- 监听 `NSWorkspace.didMountNotification` / `didUnmountNotification`，挂载或卸载卷时刷新左侧列表，并保留已有节点的展开状态。

## 项目结构

```
Package.swift                  Swift Package 定义
build.sh                       构建并打包 .app
make-icon.sh                   由 PNG 源图生成 AppIcon.icns
tools/gen-icon.swift           图标绘制脚本
Resources/
  AppIcon-1024.png             1024x1024 图标源图
  AppIcon.icns                 打包进 .app 的图标
Sources/MyFiles/
  App.swift                    应用入口
  ContentView.swift            主窗口、NSSplitViewController 分栏
  FileSystemManager.swift      卷枚举、目录与文件读取
  FileTreeView.swift           左侧磁盘和目录树（NSOutlineView）
  FileListView.swift           右侧文件列表（NSTableView）与 Enter 键处理
  FileItem.swift               文件条目模型
```

修改图标：编辑 `tools/gen-icon.swift`，然后执行

```bash
swift tools/gen-icon.swift Resources/AppIcon-1024.png
./make-icon.sh
./build.sh
```

`build.sh` 会在 PNG 比 ICNS 新时自动重新生成图标。

## 已验证行为

- 显示本机磁盘 Macintosh HD、外接磁盘、SMB/NAS 网络卷。
- 目录逐层展开、折叠，延迟读取子目录。
- 网络卷（SMB）目录可以正常浏览。
- 右侧文件图标、自然排序、上下键选择、Enter 打开。
- Enter 选中文件夹进入目录，Enter 选中文件用默认应用打开。
- 双击文件夹进入目录，双击文件用默认应用打开（文本文件打开默认编辑器，mp4 打开默认播放器）。
- 磁盘映像挂载后左侧自动出现，卸载后自动移除。
- 无权限目录显示错误提示，程序继续运行。
- 本机文件删除后进入废纸篓；网络卷文件删除前提示不可恢复，确认后直接删除并刷新列表。

## 不包含的功能

文件复制、移动、重命名、搜索、预览、标签页、书签、自定义文件关联等均未实现。
