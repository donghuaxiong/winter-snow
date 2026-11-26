# Snowglow Windows 0.2

Snowglow 的 Windows 桌面雪景版。设置沿用 macOS 版的降雪、装饰、壁纸和场景四页布局，使用同一套图标和壁纸素材。

## 下载与启动

从最新发行版下载对应芯片的 EXE。ARM 电脑和 Apple 芯片 Mac 上的 Parallels Windows 11 选 ARM64，Intel 或 AMD 电脑选 x64。下载后双击运行，程序已带上运行时。[Gitee 下载（国内）](https://gitee.com/dong-huaxiong/winter-snow/releases) · [GitHub 下载](https://github.com/donghuaxiong/winter-snow/releases/latest)

首次打开会显示设置。关闭设置窗口后可从任务栏通知区域再次打开，也可从同一菜单退出程序。Windows 收起托盘图标时，点通知区域旁的向上箭头查看。

- **窗口雪**随窗沿移动。最小化或关闭窗口后，积雪可落到下方窗口或屏幕底边。鼠标划过雪层会带起雪粉。
- **降雪**可调节雪量、速度、风向与前后层，支持冰柱、空闲后飘雪与调暗，以及全屏预览。
- **雪人**支持 2 或 3 个雪球、帽饰、表情、围巾、手臂和纽扣。可拖动、推倒重堆，或把雪人放到窗口上。窗口关闭或最小化时，窗沿的雪人会掉落。
- **装饰**支持圣诞树、窗边彩灯、提灯、礼物和倒数日历。进入桌面摆放模式可以跨屏拖动，拖到窗口标题栏即可挂靠，按 Esc 完成。开启「铲雪车可破坏装饰」后，铲雪车可移走底部的装饰或雪人。
- **壁纸**提供包括圣诞夜系列在内的 12 张图。可应用到所有显示器，随后恢复原桌面图片。
- **场景**可保存、载入和删除桌面配置，包含壁纸、降雪设置、雪人服饰和装饰位置。
- **设置文件**存放在 `%LOCALAPPDATA%\Snowglow\settings.json`。启动报错时，详情写入同目录的 `error.log`。

动态飘雪、空闲模式和全屏预览运行在 Windows 登录后的用户桌面。

## 构建

使用 .NET 10 SDK。在 macOS 或其他有 POSIX shell 的环境可以运行 `./Windows/publish.sh` 同时发布两个架构。以下命令发布单个架构，修改 `win-arm64` 可切换到 `win-x64`。

```sh
dotnet publish Windows/Snowglow.csproj -c Release -r win-arm64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false -o dist/windows/arm64
```

源代码为 C#，设置面板和绘制层使用 WPF，系统托盘使用 Windows Forms，窗口和显示器的几何信息通过 Win32 和 DWM 获取。
