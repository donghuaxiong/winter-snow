# Snowglow 雪灯桌面

让雪落在桌面、窗沿和屏幕底边。为雪人换装，挂一串彩灯，或挑一张圣诞夜壁纸。

[Gitee 下载（国内）](https://gitee.com/dong-huaxiong/winter-snow/releases) · [GitHub 下载](https://github.com/donghuaxiong/winter-snow/releases/latest) · [使用说明](#安装与启动) · [从源码构建](#从源码构建)

![Snowglow 的雪夜木屋壁纸。暖色窗灯照亮雪地，远处是深蓝色的雪山。](Resources/WinterCabin.jpg)

## 下载

国内用户可以从 [Gitee 发行版](https://gitee.com/dong-huaxiong/winter-snow/releases) 下载。打开最新版，按下表选择相同名称的附件。表格中的链接可从 GitHub 直接下载。

| 你的电脑 | 下载文件 |
| --- | --- |
| Apple 芯片 Mac 或 Intel Mac，macOS 14 及以上 | [macOS 通用版 DMG](https://github.com/donghuaxiong/winter-snow/releases/latest/download/Snowglow-macOS-Universal.dmg) |
| Intel Mac，macOS 14 及以上 | [macOS Intel 专用版 DMG](https://github.com/donghuaxiong/winter-snow/releases/latest/download/Snowglow-macOS-Intel.dmg) |
| Intel / AMD 电脑，Windows 11 | [Windows x64 EXE](https://github.com/donghuaxiong/winter-snow/releases/latest/download/Snowglow-Windows-x64.exe) |
| ARM 电脑或 Apple 芯片 Mac 上的 Parallels Windows 11 | [Windows ARM64 EXE](https://github.com/donghuaxiong/winter-snow/releases/latest/download/Snowglow-Windows-ARM64.exe) |

Mac 用户选通用版即可。Gitee 和 GitHub 的发行版均提供 `SHA256SUMS.txt`。[GitHub 校验文件直链](https://github.com/donghuaxiong/winter-snow/releases/latest/download/SHA256SUMS.txt)

## 安装与启动

**macOS**

打开 DMG，把 Snowglow 拖到「应用程序」，再从「应用程序」启动。之后可以点菜单栏的雪花图标打开设置。当前安装包使用 ad hoc 签名，尚未经过 Apple 公证。若首次打开时系统提示无法验证开发者，请先确认下载来源和校验值，再按需要使用 Apple 提供的单个应用放行方式。[Apple 的打开方式](https://support.apple.com/zh-cn/102445)

**Windows**

下载对应芯片的 EXE，双击运行。程序内置 .NET 运行时，无需另外安装。关闭设置窗后，仍可从任务栏通知区域的雪花图标打开设置或退出。如果图标被折叠，点通知区域的向上箭头。

本次 EXE 未做 Authenticode 签名，首次下载运行时可能出现 SmartScreen 提示。运行前请确认下载来源并核对 SHA-256。[Microsoft 的 SmartScreen 说明](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)

## 可以做什么

- **桌面降雪**可调节雪量、速度、风向和前后层。暂停降雪后，空中的雪会自然落完，积雪继续保留。雪会在窗沿和屏幕底部堆积，移窗时跟随，最小化或关闭时滑落。窗沿积雪太厚时，少量雪会沿露出的圆角滑下，落到下方继续堆积。光标经过积雪会扬起雪粉。
- **铲雪和冰柱**可以独立控制。底部积雪够厚时铲雪车会自动出动，也可手动发车。车是否会移除装饰由你决定。
- **桌面装饰**有雪人、圣诞树、彩灯、提灯、礼物和倒数日历。装饰可安排在桌面或挂到窗口，雪人可换帽饰、表情和围巾。
- **Mac 桌面互动**默认开启「鼠标搓雪球」。按住积雪或已有的雪球继续滚，雪球最大直径为 144 点。甩动后松手能投掷雪球，撞到屏幕边缘后碎雪会落到底部堆积。右键雪球选择「自由堆叠」，可以自定高低和位置，也可以选胡萝卜、煤球、树枝、帽子或围巾，装好后还能用鼠标调整道具。叠满三个自动成型及叠两个后右键「堆成雪人」依然可用。
- **雪球落窗**推到窗沿外时，雪球会沿原方向下坠，可以被经过的低窗接住，并随余势继续滚。每次接触窗沿会重新计算落差。连续坠落超过半个屏幕并撞到桌面底部时，雪球会碎开，碎屑会留在地面积雪中。
- 「自由挂彩灯」支持点按和拖动挂钩，用滚轮调灯线松紧。雪橇可自动飞过或手动发车，落地礼物可点开，鼠标扫过圣诞树会抖落枝头的雪。
- **Mac 降雪体验**可单独调节晶体雪花和局部阵风。全屏避让按显示器生效。自动省电会在使用电池、低电量模式或温度较高时降低更新频率，显示器休眠时暂停绘制。
- **壁纸和场景**提供 12 张冬景，其中 4 张是圣诞夜主题。可以恢复原壁纸，也可以保存整套雪况、壁纸和装饰布局。

| 功能 | macOS | Windows |
| --- | --- | --- |
| 底部积雪 | Dock 和屏幕底边 | 任务栏上沿和屏幕底边 |
| 窗口与装饰 | 支持台前调度收起时落雪，提供拖雪球工作坊和多个雪人 | 支持窗口最小化落雪和装饰跨屏摆放，当前支持一个雪人 |
| 空闲与锁屏 | 空闲预览。macOS 26 已下载过系统动态壁纸时可启用「雪夜木屋」锁屏飘雪 | 登录后的空闲飘雪、调暗和全屏预览 |

## 从源码构建

macOS 需要 Xcode 命令行工具。

```sh
./build.sh
./dist/Snowglow.app/Contents/MacOS/Snowglow --self-test
./Tools/package-macos.sh
```

`./build.sh` 生成通用应用，`--native` 仅构建当前芯片。打包脚本生成通用版和 Intel 专用版 DMG。

Windows 需要 .NET 10 SDK。在 macOS 或其他有 POSIX shell 的环境运行下方命令可同时发布两个架构。Windows 上的构建命令和故障日志位置见 [Windows 开发说明](Windows/README.md)。

```sh
./Windows/publish.sh
```

## 许可证

[MIT](LICENSE)
