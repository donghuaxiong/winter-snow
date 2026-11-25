# Snowglow 雪灯桌面

Snowglow 是 macOS 14 或更新版本的原生菜单栏应用，支持 Apple 芯片、Intel 芯片和多显示器。双击 `dist/Snowglow.app`，再从菜单栏的雪花打开工作台。

- **降雪**可以调节密度、风向、速度和窗口前后层。雪会积在窗口、程序坞、桌面小组件和屏幕底部。光标扫过雪层会拨开积雪，带起雪粉。最小化窗口、台前调度收起窗口，或握住标题栏左右快速晃动，窗沿的雪会掉到屏幕底部并继续堆积。
- **锁屏飘雪**适用于已下载过系统动态壁纸的 macOS 26。通过降雪设置或菜单栏启用后，「雪夜木屋」会同时成为锁屏和桌面壁纸。可选「恢复原壁纸」。
- **铲雪车**默认启用。每块屏幕底部积到一定厚度，铲雪车就会驶过来，一路把雪推开。铲板翻起的部分雪块会落回屏幕底部，留下薄薄的雪脊。可以在「降雪」页关闭自动铲雪，或点「立即铲雪」手动运行一次。
- **装饰**可以添加雪人、圣诞树、彩灯、提灯、礼物、花环和倒数日历。“在桌面摆放”允许拖动装饰。也可用设置面板内的位置控件操作，或选一个真实窗口把装饰固定在它上面。
- **雪夜木屋**在「降雪」页或菜单栏中一键应用。它会启用飘雪、积雪、自动铲雪，并换上原创木屋壁纸。
- **堆雪人**从菜单栏或「装饰」页进入。选一个窗口或桌面，从大到小拖动叠放雪球。装好后在衣帽间换帽子、表情、围巾和身体，并能分享透明背景的雪人图。也可右键雪人选择「推倒重堆」，再点任一雪球把雪人堆起来。窗口上的雪人会跟随移动，最小化时掉落并散成雪粉。
- **壁纸**提供 32 张冬景，应用后可在同一页恢复之前的壁纸。
- **场景**可以保存当前雪况、壁纸和装饰布局。点菜单栏的雪花也可暂停降雪、清雪、预览空闲模式或退出。

空闲效果由 Snowglow 自行触发。macOS 的屏幕保护程序、锁屏和屏幕休眠仍按系统设置工作。应用通过窗口的位置和尺寸绘制积雪，设置保存在这台 Mac 上。

## 构建与自检

在装有 Xcode 的 Mac 上运行：

```sh
./build.sh
./dist/Snowglow.app/Contents/MacOS/Snowglow --self-test
```

`./build.sh --native` 仅构建当前 Mac 的架构。构建产出位于 `dist/Snowglow.app`，使用本地 ad hoc 签名。

使用 `swift Tools/render-lock-snow.swift Resources` 重新生成随应用打包的锁屏雪景。

## 雪夜木屋壁纸

`Resources/WinterCabin.jpg` 由内置 ImageGen 生成。原始提示词如下。

> Use case: illustration-story. Asset type: full-bleed ultrawide macOS desktop wallpaper for Snowglow, 16:9 landscape. Create an original high-detail winter storybook painting, warm Christmas cabin lights against a rich cobalt winter night. In the left third: a close and clearly legible timber A-frame chalet, with deeply snow piled on roofs, solid log porch, carved railing, amber lanterns and a tidy strand of tiny warm yellow bulbs along its gable and porch. Honey-orange light shines through the divided windows and casts warm peach accents onto the snow around the steps. Cabin roof peak at about 35 percent of image height, snow-filled path and dark rounded boulders in foreground. Snow-laden black spruce branches enter from the top left and drape along the upper edge, their underside catching some peach firelight. Central and right thirds have airy open deep Prussian blue night sky with a few tiny stars, ridged snowy mountains and dark evergreens concentrated toward the horizon and right edge, leaving dark low-contrast negative space for desktop windows on the right. Ground is undulating blue and lilac powder with amber reflection from the house. Winter dusk atmospheric perspective, crisp graphic snow banks, painterly dark spruce needles and detailed warm carved timber, rich atmospheric depth, balanced saturation, convincing contrast. This is pure wallpaper artwork without any lettering, watermarks, laptop, windows overlays, software interfaces, pointer, snowman, vehicle, or borders. No falling snow specks besides a few distant stars, because the app renders moving snowfall separately. Fill the frame.
