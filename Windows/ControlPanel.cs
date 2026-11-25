using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Snowglow.Windows;

internal sealed class ControlPanel : Window
{
    private enum Page { Snow, Decorations, Wallpaper, Scenes }
    private sealed record Destination(Page Page, string Name, string Icon, string Query, string? Section = null);
    private static readonly Destination[] Navigation =
    [
        new(Page.Snow, "降雪", "snow", "雪花 速度 密度 风向"),
        new(Page.Decorations, "装饰", "decorations", "圣诞树 雪人 衣帽间 彩灯 日历"),
        new(Page.Wallpaper, "壁纸", "wallpaper", "圣诞夜 桌面 图片"),
        new(Page.Scenes, "场景", "scenes", "保存 载入")
    ];
    private static readonly Destination[] QuickLinks =
    [
        new(Page.Snow, "降雪参数", "snow", "密度 速度 风向 位置", "snow"),
        new(Page.Snow, "积雪与铲雪", "plow", "冰柱 碰撞 任务栏", "plow"),
        new(Page.Snow, "空闲模式", "moon", "空闲 调暗", "idle"),
        new(Page.Snow, "雪夜木屋", "cabin", "木屋", "cabin")
    ];
    private readonly DesktopController desktop;
    private readonly StackPanel navigation = new();
    private readonly StackPanel content = new();
    private readonly ScrollViewer scroll;
    private readonly TextBlock status;
    private readonly TextBlock title;
    private readonly TextBlock detail;
    private readonly Image pageIcon;
    private readonly TextBox search;
    private readonly Button snowfall;
    private readonly List<Action> refreshers = [];
    private readonly Dictionary<string, FrameworkElement> sections = [];
    private readonly Brush surface, sidebar, card, buttonFill, active, ink, muted, border, blue, onBlue;
    private readonly Style roundedButton, switchStyle;
    private Page page;
    private bool updating;
    private string? selectedWallpaper;
    private Guid? selectedDecoration;
    private Guid[] listedDecorations = [];

    public ControlPanel(DesktopController desktop)
    {
        this.desktop = desktop;
        bool dark = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "AppsUseLightTheme", 1) is int value && value == 0;
        bool contrast = SystemParameters.HighContrast;
        Brush ColorFor(uint light, uint night) => SnowArt.Ink(dark ? night : light);
        surface = contrast ? SystemColors.WindowBrush : ColorFor(0xFFFCFDFF, 0xFF1B202A);
        sidebar = contrast ? SystemColors.ControlBrush : ColorFor(0xFFF0F3F8, 0xFF171C25);
        card = contrast ? SystemColors.ControlBrush : ColorFor(0xFFF1F4F8, 0xFF242C38);
        buttonFill = contrast ? SystemColors.ControlBrush : ColorFor(0xFFE5EBF4, 0xFF323C4C);
        active = contrast ? SystemColors.HighlightBrush : ColorFor(0xFFDFE9FA, 0xFF2C4260);
        ink = contrast ? SystemColors.WindowTextBrush : ColorFor(0xFF182235, 0xFFE5EBF4);
        muted = contrast ? SystemColors.WindowTextBrush : ColorFor(0xFF566278, 0xFFAAB6C8);
        border = contrast ? SystemColors.WindowTextBrush : ColorFor(0xFFDCE3ED, 0xFF394454);
        blue = contrast ? SystemColors.HighlightBrush : ColorFor(0xFF235FAD, 0xFF9BC7FF);
        onBlue = contrast ? SystemColors.HighlightTextBrush : ColorFor(0xFFFFFFFF, 0xFF131D2A);
        roundedButton = (Style)XamlReader.Parse(ButtonStyle);
        switchStyle = (Style)XamlReader.Parse(SwitchStyle);

        Title = "Snowglow 雪灯桌面";
        Width = 940;
        Height = Math.Min(730, SystemParameters.WorkArea.Height * .94);
        MinWidth = 780;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = surface;
        Foreground = ink;
        FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI");
        FontSize = 14;
        Icon = Artwork.Icon("snow");
        UseLayoutRounding = true;

        var shell = new Grid { Background = surface };
        shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(184) });
        shell.ColumnDefinitions.Add(new ColumnDefinition());
        Content = shell;

        var rail = new DockPanel { Background = sidebar, LastChildFill = true };
        shell.Children.Add(rail);
        var searchLine = new DockPanel { LastChildFill = true };
        var magnifier = Picture("search", 17);
        magnifier.Margin = new Thickness(0, 0, 8, 0);
        searchLine.Children.Add(magnifier);
        var clearSearch = ActionButton("清空搜索", () => search!.Clear(), "clear");
        clearSearch.Content = Picture("clear", 14);
        clearSearch.Padding = new Thickness(4);
        clearSearch.MinHeight = 25;
        clearSearch.Visibility = Visibility.Collapsed;
        DockPanel.SetDock(clearSearch, Dock.Right);
        searchLine.Children.Add(clearSearch);
        search = new TextBox
        {
            Background = Brushes.Transparent, Foreground = ink, BorderThickness = new Thickness(0),
            Padding = new Thickness(2), VerticalContentAlignment = VerticalAlignment.Center, ToolTip = "搜索设置"
        };
        AutomationProperties.SetName(search, "搜索设置");
        var hint = Caption("搜索设置", 13);
        hint.IsHitTestVisible = false;
        var searchInput = new Grid();
        searchInput.Children.Add(search);
        searchInput.Children.Add(hint);
        hint.VerticalAlignment = VerticalAlignment.Center;
        hint.Margin = new Thickness(2, 0, 0, 0);
        searchLine.Children.Add(searchInput);
        var searchBox = new Border
        {
            Margin = new Thickness(12, 18, 12, 14), Padding = new Thickness(10, 2, 6, 2), Height = 38,
            Background = buttonFill, CornerRadius = new CornerRadius(18), Child = searchLine
        };
        DockPanel.SetDock(searchBox, Dock.Top);
        rail.Children.Add(searchBox);
        search.TextChanged += (_, _) =>
        {
            hint.Visibility = search.Text.Length == 0 && !search.IsKeyboardFocused ? Visibility.Visible : Visibility.Collapsed;
            clearSearch.Visibility = search.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            RefreshNavigation();
        };
        search.GotKeyboardFocus += (_, _) => hint.Visibility = Visibility.Collapsed;
        search.LostKeyboardFocus += (_, _) => hint.Visibility = search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        search.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && Matches().FirstOrDefault() is { } result) Choose(result);
            if (e.Key == Key.Escape) search.Clear();
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control) { search.Focus(); e.Handled = true; }
        };

        var branding = IconText("snow", "Snowglow", 32);
        branding.Margin = new Thickness(16, 8, 8, 17);
        DockPanel.SetDock(branding, Dock.Bottom);
        rail.Children.Add(branding);
        rail.Children.Add(new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = navigation, Padding = new Thickness(10, 0, 10, 0)
        });

        var main = new DockPanel { LastChildFill = true };
        Grid.SetColumn(main, 1);
        shell.Children.Add(main);
        var head = new DockPanel { Margin = new Thickness(26, 19, 26, 17), LastChildFill = true };
        snowfall = ActionButton("降雪", () => { desktop.Options.Snow = !desktop.Options.Snow; desktop.Apply(); });
        DockPanel.SetDock(snowfall, Dock.Right);
        snowfall.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(snowfall);
        pageIcon = Picture("snow", 40);
        pageIcon.Margin = new Thickness(0, 0, 12, 0);
        head.Children.Add(pageIcon);
        var copy = new StackPanel();
        head.Children.Add(copy);
        title = new TextBlock { FontSize = 27, FontWeight = FontWeights.Bold, Foreground = ink };
        AutomationProperties.SetHeadingLevel(title, AutomationHeadingLevel.Level1);
        detail = Caption("", 12);
        detail.Margin = new Thickness(0, 4, 7, 0);
        detail.TextWrapping = TextWrapping.Wrap;
        copy.Children.Add(title);
        copy.Children.Add(detail);
        DockPanel.SetDock(head, Dock.Top);
        main.Children.Add(head);

        status = Caption("Snowglow 0.2", 12);
        status.TextWrapping = TextWrapping.Wrap;
        status.Margin = new Thickness(26, 8, 26, 8);
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        var footer = new Border { BorderBrush = border, BorderThickness = new Thickness(0, 1, 0, 0), Child = status };
        DockPanel.SetDock(footer, Dock.Bottom);
        main.Children.Add(footer);
        content.Margin = new Thickness(26, 2, 26, 20);
        scroll = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        main.Children.Add(scroll);
        desktop.Changed += Refresh;
        Closed += (_, _) => { desktop.Changed -= Refresh; desktop.CancelPlacement(); desktop.StopEditingDecorations(); };
        Open(Page.Snow);
    }

    private IEnumerable<Destination> Matches()
    {
        string query = search.Text.Trim();
        return query.Length == 0 ? Navigation : QuickLinks.Concat(Navigation).Where(entry =>
            (entry.Name + " " + entry.Query).Contains(query, StringComparison.OrdinalIgnoreCase));
    }

    private void RefreshNavigation()
    {
        navigation.Children.Clear();
        var heading = Caption(search.Text.Trim().Length == 0 ? "设置" : "搜索结果", 12);
        heading.Margin = new Thickness(8, 0, 0, 8);
        navigation.Children.Add(heading);
        var matches = Matches().ToArray();
        if (matches.Length == 0) navigation.Children.Add(Caption("没有找到相关设置", 12));
        foreach (Destination destination in matches)
        {
            var button = ActionButton(destination.Name, () => Choose(destination), destination.Icon);
            button.Background = destination.Page == page && destination.Section is null ? active : Brushes.Transparent;
            button.HorizontalContentAlignment = HorizontalAlignment.Left;
            button.MinHeight = 44;
            button.Margin = new Thickness(0, 0, 0, 3);
            button.Padding = new Thickness(10, 6, 8, 6);
            navigation.Children.Add(button);
        }
    }

    private void Choose(Destination destination)
    {
        search.Clear();
        Open(destination.Page);
        if (destination.Section is { } section && sections.TryGetValue(section, out var target))
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => target.BringIntoView()));
    }

    private void Open(Page destination, bool preserveScroll = false)
    {
        double offset = preserveScroll ? scroll.VerticalOffset : 0;
        page = destination;
        content.Children.Clear();
        refreshers.Clear();
        sections.Clear();
        pageIcon.Source = Artwork.Icon(Navigation[(int)page].Icon);
        (title.Text, detail.Text) = destination switch
        {
            Page.Snow => ("桌面降雪", "雪会落在窗口和任务栏上。轻晃窗口可以抖落积雪。"),
            Page.Decorations => ("桌面装饰", "装饰可以摆在桌面，也可以挂在窗口上。"),
            Page.Wallpaper => ("冬日壁纸", "12 张雪景和圣诞夜壁纸，可应用到所有显示器。"),
            _ => ("冬日场景", "保存当前雪况、壁纸和装饰布局。")
        };
        switch (destination)
        {
            case Page.Snow: BuildWeather(); break;
            case Page.Decorations: BuildDecorations(); break;
            case Page.Wallpaper: BuildWallpapers(); break;
            case Page.Scenes: BuildScenes(); break;
        }
        RefreshNavigation();
        Refresh();
        scroll.ScrollToVerticalOffset(offset);
    }

    private void Refresh()
    {
        if (page == Page.Decorations && !listedDecorations.SequenceEqual(desktop.Options.Decorations.Select(item => item.Id)))
        {
            Open(page, preserveScroll: true);
            return;
        }
        updating = true;
        string label = desktop.Options.Snow ? "暂停降雪" : "开始降雪";
        snowfall.Content = IconText(desktop.Options.Snow ? "pause" : "play", label, 17);
        snowfall.Background = desktop.Options.Snow ? buttonFill : blue;
        snowfall.Foreground = desktop.Options.Snow ? ink : onBlue;
        AutomationProperties.SetName(snowfall, label);
        foreach (Action update in refreshers) update();
        updating = false;
    }

    private void Report(string message)
    {
        status.Text = message;
        if (UIElementAutomationPeer.FromElement(status) is { } peer)
            peer.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    private void BuildWeather()
    {
        var preview = new Grid();
        preview.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(194) });
        preview.ColumnDefinitions.Add(new ColumnDefinition());
        var previewImage = new SampleWeather(desktop) { Height = 104, ClipToBounds = true };
        preview.Children.Add(RoundedImage(previewImage, 10));
        var actions = new StackPanel { Margin = new Thickness(15, 2, 0, 0) };
        Grid.SetColumn(actions, 1);
        preview.Children.Add(actions);
        actions.Children.Add(new TextBlock { Text = "实时预览", FontWeight = FontWeights.SemiBold, FontSize = 15 });
        actions.Children.Add(Caption("拖动滑块查看降雪变化。"));
        var buttons = Actions(actions);
        buttons.Children.Add(ActionButton("全屏预览", () =>
        {
            WindowState = WindowState.Minimized;
            desktop.Preview(() => { if (IsLoaded) { WindowState = WindowState.Normal; Activate(); } });
        }, "preview", emphasis: true));
        buttons.Children.Add(ActionButton("清除积雪", () => { desktop.ClearSnow(); Report("已清除积雪。"); }));
        content.Children.Add(Card(preview));

        var weather = Section("降雪参数", "snow", "snow");
        Scale(weather, "降雪密度", "snow", 0, 1, () => desktop.Options.Density, value => Set(o => o.Density = value));
        Scale(weather, "下落速度", "speed", 0, 1, () => desktop.Options.Speed, value => Set(o => o.Speed = value));
        Scale(weather, "风向与风力", "wind", -1, 1, () => desktop.Options.Wind, value => Set(o => o.Wind = value));
        Pick(weather, "降雪位置", "layer", ["所有窗口后方", "当前窗口后方", "所有窗口前方"],
            () => (int)desktop.Options.Layer, index => Set(o => o.Layer = (SnowLayer)index));

        var snowpack = Section("积雪与铲雪", "plow", "plow");
        Toggle(snowpack, "在窗口和屏幕底部积雪", "accumulation", () => desktop.Options.Accumulation, _ => desktop.ToggleAccumulation());
        Toggle(snowpack, "形成冰柱", "icicles", () => desktop.Options.Icicles, value => Set(o => o.Icicles = value),
            enabled: () => desktop.Options.Accumulation);
        var plow = ActionButton("立即铲雪", () => Report(desktop.PlowNow() ? "铲雪车已出发。" : "当前显示器已有铲雪车运行。"));
        Toggle(snowpack, "自动铲雪", "plow", () => desktop.Options.AutomaticPlow, value => Set(o => o.AutomaticPlow = value),
            "底部积雪达到一定厚度时自动发车。", () => desktop.Options.Accumulation, plow);
        Toggle(snowpack, "铲雪车可破坏装饰", "trash", () => desktop.Options.PlowCollision, value => Set(o => o.PlowCollision = value),
            "铲雪车撞到的装饰会被移除。");

        var idle = Section("空闲模式", "moon", "idle");
        int[] delays = [0, 30, 60, 120, 300, 600];
        Pick(idle, "空闲后开启", "idleTime", ["关闭", "30 秒", "1 分钟", "2 分钟", "5 分钟", "10 分钟"],
            () => Array.IndexOf(delays, desktop.Options.IdleSeconds),
            index => Set(o => { o.IdleSeconds = delays[index]; if (index == 0) o.OnlyIdle = false; }));
        Toggle(idle, "仅空闲时降雪", "moon", () => desktop.Options.OnlyIdle, value => Set(o => o.OnlyIdle = value),
            enabled: () => desktop.Options.IdleSeconds != 0);
        Toggle(idle, "空闲时调暗桌面", "dim", () => desktop.Options.IdleDim, value => Set(o => o.IdleDim = value),
            enabled: () => desktop.Options.IdleSeconds != 0);

        var cabin = Section("雪夜木屋", "cabin", "cabin");
        var apply = ActionButton("应用场景", () => Report(desktop.ApplyCabin()), emphasis: true);
        Row(cabin, "一键应用木屋壁纸、飘雪和自动铲雪。", "cabin", apply);
    }

    private void BuildDecorations()
    {
        listedDecorations = desktop.Options.Decorations.Select(item => item.Id).ToArray();
        var adding = Section("添加装饰", "decorations");
        var buttons = Actions(adding);
        buttons.Children.Add(ActionButton("雪人", () => { desktop.AddOrResetSnowman(); Report("雪人已放到屏幕底边。"); }, "snowman"));
        foreach (DecorationKind kind in Enum.GetValues<DecorationKind>())
            buttons.Children.Add(ActionButton(DecorationArt.Name(kind), () =>
            {
                selectedDecoration = desktop.AddDecoration(kind).Id;
                Open(page, true);
            }, DecorationArt.Key(kind)));
        buttons.Children.Add(ActionButton("选窗口挂灯", () =>
        {
            selectedDecoration = desktop.AddDecoration(DecorationKind.Lights).Id;
            Place(selectedDecoration.Value, attach: true);
        }, "windowLights"));

        var snowman = Section("雪人衣帽间", "snowman");
        Pick(snowman, "雪球", "snow", ["两个", "三个"],
            () => desktop.Options.Snowballs - 2, index => Set(o => o.Snowballs = index + 2));
        Pick(snowman, "帽饰", "snowman", ["经典礼帽", "圣诞帽", "蓝色针织帽", "皇冠", "耳罩", "鹿角", "精灵帽", "无帽"],
            () => (int)desktop.Options.Outfit, index => Set(o => o.Outfit = (SnowmanOutfit)index));
        Pick(snowman, "表情", "snowman", ["微笑", "开心", "犯困", "惊讶"],
            () => (int)desktop.Options.Face, index => Set(o => o.Face = (SnowmanFace)index));
        Pick(snowman, "围巾", "decorations", ["随帽饰", "红色", "松绿", "冰蓝", "暖金", "无围巾"],
            () => (int)desktop.Options.Scarf, index => Set(o => o.Scarf = (SnowmanScarf)index));
        Toggle(snowman, "树枝手臂", "tree", () => desktop.Options.Arms, value => Set(o => o.Arms = value));
        Toggle(snowman, "雪球纽扣", "snow", () => desktop.Options.Buttons, value => Set(o => o.Buttons = value));
        var personActions = Actions(snowman);
        personActions.Children.Add(ActionButton("把雪人移到底边", desktop.AddOrResetSnowman));
        personActions.Children.Add(ActionButton("把雪人放到窗口上", () =>
        {
            WindowState = WindowState.Minimized;
            desktop.PlaceSnowmanOnWindow(message =>
            {
                if (!IsLoaded) return;
                WindowState = WindowState.Normal;
                Activate();
                Report(message);
            });
        }, "windowLights"));
        personActions.Children.Add(ActionButton("移除雪人", desktop.RemoveSnowman, "trash"));
        snowman.Children.Add(Caption("可在桌面拖动雪人，右键推倒，单击雪球重堆。"));

        var decorated = Section("已摆放的装饰", "decorations");
        Toggle(decorated, "显示装饰", "decorations", () => desktop.Options.ShowDecorations,
            value => Set(o => o.ShowDecorations = value));
        if (desktop.Options.Decorations.Count == 0)
        {
            decorated.Children.Add(Caption("添加的装饰会出现在这里。"));
            return;
        }
        var editActions = Actions(decorated);
        editActions.Children.Add(ActionButton("在桌面拖动装饰", () =>
        {
            if (!desktop.Options.ShowDecorations) Set(o => o.ShowDecorations = true);
            WindowState = WindowState.Minimized;
            desktop.EditDecorations(() =>
            {
                if (!IsLoaded) return;
                WindowState = WindowState.Normal;
                Activate();
                Open(Page.Decorations, true);
                Report("装饰布局已保存。");
            });
        }, "windowLights"));
        editActions.Children.Add(Caption("拖到窗口标题栏可挂靠。按 Esc 完成。"));
        var choices = Actions(decorated);
        var item = desktop.Options.Decorations.FirstOrDefault(d => d.Id == selectedDecoration) ?? desktop.Options.Decorations[0];
        selectedDecoration = item.Id;
        foreach (Decoration decoration in desktop.Options.Decorations)
        {
            string caption = DecorationArt.Name(decoration.Kind) + (decoration.Window is null ? "" : " · 窗口");
            var button = ActionButton(caption, () => { selectedDecoration = decoration.Id; Open(page, true); }, DecorationArt.Key(decoration.Kind));
            if (item.Id == decoration.Id) button.Background = active;
            choices.Children.Add(button);
        }

        var inspector = Section(DecorationArt.Name(item.Kind), DecorationArt.Key(item.Kind));
        Decoration Current() => desktop.Options.Decorations.FirstOrDefault(d => d.Id == item.Id) ?? item;
        void Edit(Func<Decoration, Decoration> update) => desktop.ChangeDecoration(item.Id, update);
        Scale(inspector, "大小", DecorationArt.Key(item.Kind), .5, 2, () => Current().Scale, value => Edit(d => d with { Scale = value }));
        Scale(inspector, item.Window is null ? "水平位置" : "沿窗移动", "layer", 0, 1,
            () => Current().X, value => Edit(d => d with { X = value }));
        if (item.Window is null)
            Scale(inspector, "垂直位置", "speed", 0, 1, () => Current().Y, value => Edit(d => d with { Y = value }));
        if (item.Kind != DecorationKind.Calendar)
            Scale(inspector, "旋转", "wind", -180, 180, () => Current().Rotation, value => Edit(d => d with { Rotation = value }), degrees: true);
        if (item.Kind == DecorationKind.Lights)
        {
            Pick(inspector, "配色", "lights", ["经典", "冰蓝", "暖金"], () => Current().Palette, index => Edit(d => d with { Palette = index }));
            Pick(inspector, "灯效", "decorations", ["常亮", "闪烁", "追逐"], () => Current().LightEffect, index => Edit(d => d with { LightEffect = index }));
        }
        if (item.Kind == DecorationKind.Calendar)
        {
            int available = DecorationArt.AvailableDoors(DateTime.Now);
            inspector.Children.Add(Caption(available == 0 ? "12 月 1 日起每天开启一格。" : $"今天可以开启前 {available} 格。"));
            var doors = Actions(inspector);
            for (int day = 1; day <= 25; day++)
            {
                int date = day;
                bool opened = (item.Opened & (1 << (date - 1))) != 0;
                var door = ActionButton(date.ToString(), () =>
                {
                    Edit(d => d with { Opened = d.Opened | (1 << (date - 1)) });
                    Open(page, true);
                }, opened ? "star" : null);
                door.IsEnabled = !opened && date <= available;
                doors.Children.Add(door);
            }
        }
        var edits = Actions(inspector);
        edits.Children.Add(ActionButton("在桌面摆放", () => Place(item.Id, attach: false)));
        edits.Children.Add(ActionButton(item.Window is null ? "放到窗口上" : "更换窗口", () => Place(item.Id, attach: true), "windowLights"));
        edits.Children.Add(ActionButton("移除装饰", () => desktop.RemoveDecoration(item.Id), "trash"));
    }

    private void Place(Guid id, bool attach)
    {
        WindowState = WindowState.Minimized;
        desktop.PlaceDecoration(id, attach, message =>
        {
            if (!IsLoaded) return;
            WindowState = WindowState.Normal;
            Activate();
            Open(Page.Decorations, true);
            Report(message);
        });
    }

    private void BuildWallpapers()
    {
        if (Wallpaper.Find(selectedWallpaper) is null) selectedWallpaper = desktop.Options.Wallpaper ?? Wallpaper.Cabin;
        var actions = Actions(content);
        actions.HorizontalAlignment = HorizontalAlignment.Right;
        var restore = ActionButton("恢复原壁纸", () => Report(desktop.RestoreWallpaper()));
        actions.Children.Add(restore);
        var apply = ActionButton("设为壁纸", () =>
        {
            if (Wallpaper.Find(selectedWallpaper) is { } art) Report(desktop.ApplyWallpaper(art));
        }, emphasis: true);
        actions.Children.Add(apply);
        refreshers.Add(() => restore.IsEnabled = desktop.Options.PreviousBackground is not null);
        Gallery("圣诞夜", "tree", true, 4);
        Gallery("冬日雪景", "snow", false, 3);
    }

    private void Gallery(string caption, string icon, bool christmas, int columns)
    {
        var heading = Heading(caption, icon);
        heading.Margin = new Thickness(1, 12, 0, 8);
        content.Children.Add(heading);
        var grid = new System.Windows.Controls.Primitives.UniformGrid { Columns = columns };
        content.Children.Add(grid);
        foreach (Wallpaper art in Wallpaper.All.Where(item => item.Christmas == christmas))
        {
            var thumb = new Image
            {
                Source = Artwork.Image(art.Resource, 560), Stretch = Stretch.UniformToFill,
                Height = christmas ? 88 : 118
            };
            var wrap = new StackPanel();
            wrap.Children.Add(RoundedImage(thumb, 9));
            var label = new DockPanel { Margin = new Thickness(9, 5, 7, 6) };
            var badge = Picture("applied", 16);
            DockPanel.SetDock(badge, Dock.Right);
            label.Children.Add(badge);
            label.Children.Add(new TextBlock { Text = art.Name, FontWeight = FontWeights.Medium });
            wrap.Children.Add(label);
            var button = ActionButton(art.Name, () => { selectedWallpaper = art.Key; Refresh(); });
            button.Content = wrap;
            button.Background = card;
            button.Padding = new Thickness(1);
            button.Margin = new Thickness(1, 0, 8, 9);
            button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            grid.Children.Add(button);
            refreshers.Add(() =>
            {
                bool current = desktop.Options.Wallpaper == art.Key;
                badge.Visibility = current ? Visibility.Visible : Visibility.Collapsed;
                AutomationProperties.SetItemStatus(button, current ? "当前壁纸" : selectedWallpaper == art.Key ? "已选择" : "");
                button.BorderBrush = selectedWallpaper == art.Key ? blue : border;
                button.BorderThickness = new Thickness(selectedWallpaper == art.Key ? 2 : 1);
            });
        }
    }

    private void BuildScenes()
    {
        var adding = Section("新场景", "scenes");
        var name = new TextBox { MinWidth = 225, MinHeight = 33, VerticalContentAlignment = VerticalAlignment.Center };
        AutomationProperties.SetName(name, "场景名称");
        void Save()
        {
            if (string.IsNullOrWhiteSpace(name.Text)) return;
            string caption = name.Text.Trim();
            desktop.SaveScene(caption);
            Open(page, true);
            Report($"已保存「{caption}」。");
        }
        var save = ActionButton("保存当前场景", Save, emphasis: true);
        save.IsEnabled = false;
        name.TextChanged += (_, _) => save.IsEnabled = !string.IsNullOrWhiteSpace(name.Text);
        name.KeyDown += (_, e) => { if (e.Key == Key.Enter) Save(); };
        var actions = Actions(adding);
        actions.Children.Add(name);
        actions.Children.Add(save);
        var saved = Section("已保存", "archive");
        if (desktop.Options.Scenes.Count == 0) saved.Children.Add(Caption("保存的场景会显示在这里。"));
        foreach (SavedScene scene in desktop.Options.Scenes)
        {
            var commands = new StackPanel { Orientation = Orientation.Horizontal };
            commands.Children.Add(ActionButton("载入", () => { Report(desktop.LoadScene(scene)); Open(Page.Scenes, true); }));
            commands.Children.Add(ActionButton("删除场景 " + scene.Name, () =>
            {
                desktop.Options.Scenes.RemoveAll(entry => entry.Id == scene.Id);
                desktop.Apply();
                Open(page, true);
            }, "trash", iconOnly: true));
            Row(saved, scene.Name, "scenes", commands);
        }
    }

    private void Set(Action<Settings> update)
    {
        update(desktop.Options);
        desktop.Apply();
    }

    private StackPanel Section(string caption, string icon, string? key = null)
    {
        var group = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
        group.Children.Add(Heading(caption, icon));
        var rows = new StackPanel();
        group.Children.Add(Card(rows));
        content.Children.Add(group);
        if (key is not null) sections.Add(key, group);
        return rows;
    }

    private FrameworkElement Heading(string text, string icon)
    {
        var result = IconText(icon, text, 17);
        result.Margin = new Thickness(1, 0, 0, 7);
        var caption = (TextBlock)result.Children[1];
        caption.FontWeight = FontWeights.SemiBold;
        caption.Foreground = muted;
        AutomationProperties.SetHeadingLevel(caption, AutomationHeadingLevel.Level2);
        return result;
    }

    private Border Card(UIElement child) => new()
    {
        Background = card, Child = child, Padding = new Thickness(11, 6, 11, 7), CornerRadius = new CornerRadius(14)
    };

    private void Row(Panel panel, string text, string icon, FrameworkElement control, string? description = null)
    {
        if (panel.Children.Count > 0)
            panel.Children.Add(new Border { Height = 1, Background = border, Margin = new Thickness(37, 0, 0, 0) });
        var row = new DockPanel { LastChildFill = true, MinHeight = 43, Margin = new Thickness(1, 0, 1, 0) };
        control.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(control, Dock.Right);
        row.Children.Add(control);
        var image = Picture(icon, 25);
        image.Margin = new Thickness(1, 0, 10, 0);
        row.Children.Add(image);
        var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = text, FontWeight = FontWeights.Medium, TextWrapping = TextWrapping.Wrap });
        if (description is not null) copy.Children.Add(Caption(description, 11));
        row.Children.Add(copy);
        panel.Children.Add(row);
    }

    private void Toggle(Panel panel, string name, string icon, Func<bool> read, Action<bool> write,
        string? description = null, Func<bool>? enabled = null, Button? extra = null)
    {
        var check = new CheckBox
        {
            Style = switchStyle, Background = buttonFill, BorderBrush = border, Foreground = blue,
            Width = 44, Height = 31, VerticalAlignment = VerticalAlignment.Center
        };
        AutomationProperties.SetName(check, name);
        check.Click += (_, _) => { if (!updating) write(check.IsChecked == true); };
        FrameworkElement element = check;
        if (extra is not null)
        {
            var group = new StackPanel { Orientation = Orientation.Horizontal };
            extra.Margin = new Thickness(0, 0, 10, 0);
            group.Children.Add(extra);
            group.Children.Add(check);
            element = group;
        }
        Row(panel, name, icon, element, description);
        refreshers.Add(() =>
        {
            check.IsChecked = read();
            element.IsEnabled = enabled?.Invoke() ?? true;
        });
    }

    private void Scale(Panel panel, string name, string icon, double min, double max, Func<float> read,
        Action<float> write, bool degrees = false)
    {
        var slider = new Slider
        {
            Minimum = min, Maximum = max, Width = 145, VerticalAlignment = VerticalAlignment.Center,
            SmallChange = degrees ? 1 : .02, LargeChange = degrees ? 10 : .10, IsMoveToPointEnabled = true
        };
        var group = new StackPanel { Orientation = Orientation.Horizontal };
        var amount = Caption("", 12);
        amount.Width = 49;
        amount.TextAlignment = TextAlignment.Right;
        amount.VerticalAlignment = VerticalAlignment.Center;
        group.Children.Add(slider);
        group.Children.Add(amount);
        AutomationProperties.SetName(slider, name);
        slider.ValueChanged += (_, eventArgs) => { if (!updating) write((float)eventArgs.NewValue); };
        Row(panel, name, icon, group);
        refreshers.Add(() =>
        {
            slider.Value = read();
            amount.Text = degrees ? $"{read():0}°" : $"{read():0%}";
        });
    }

    private void Pick(Panel panel, string name, string icon, string[] entries, Func<int> read, Action<int> write)
    {
        var picker = new ComboBox { ItemsSource = entries, MinWidth = 148, MinHeight = 31, VerticalContentAlignment = VerticalAlignment.Center };
        AutomationProperties.SetName(picker, name);
        picker.SelectionChanged += (_, _) => { if (!updating && picker.SelectedIndex >= 0) write(picker.SelectedIndex); };
        Row(panel, name, icon, picker);
        refreshers.Add(() => picker.SelectedIndex = read());
    }

    private Button ActionButton(string caption, Action action, string? icon = null, bool emphasis = false, bool iconOnly = false)
    {
        var result = new Button
        {
            Content = iconOnly && icon is not null ? Picture(icon, 17) : icon is null ? caption : IconText(icon, caption, 19),
            Style = roundedButton, Background = emphasis ? blue : buttonFill, Foreground = emphasis ? onBlue : ink,
            BorderBrush = Brushes.Transparent, Padding = new Thickness(10, 4, 10, 4), MinHeight = 34,
            Margin = new Thickness(0, 2, 7, 2),
            FontWeight = FontWeights.SemiBold
        };
        result.Click += (_, _) => action();
        AutomationProperties.SetName(result, caption);
        return result;
    }

    private WrapPanel Actions(Panel parent)
    {
        var panel = new WrapPanel { Margin = new Thickness(0, 5, 0, 6) };
        parent.Children.Add(panel);
        return panel;
    }

    internal void ValidatePages(string? wallpaperPreview = null)
    {
        var root = (FrameworkElement)Content;
        foreach (Page destination in Enum.GetValues<Page>())
        {
            Open(destination);
            root.Measure(new Size(940, 690));
            root.Arrange(new Rect(0, 0, 940, 690));
            root.UpdateLayout();
            if (content.Children.Count == 0) throw new InvalidOperationException($"Empty settings page: {destination}");
            if (destination == Page.Wallpaper && wallpaperPreview is not null)
            {
                var output = new RenderTargetBitmap(940, 690, 96, 96, PixelFormats.Pbgra32);
                output.Render(root);
                using var file = File.Create(wallpaperPreview);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(output));
                encoder.Save(file);
            }
        }
    }

    private TextBlock Caption(string label, double size = 12) => new() { Text = label, Foreground = muted, FontSize = size };
    private static Image Picture(string icon, double size) =>
        new() { Source = Artwork.Icon(icon), Width = size, Height = size, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Center };

    private static StackPanel IconText(string icon, string caption, double size)
    {
        var result = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var picture = Picture(icon, size);
        picture.Margin = new Thickness(0, 0, 7, 0);
        result.Children.Add(picture);
        result.Children.Add(new TextBlock { Text = caption, VerticalAlignment = VerticalAlignment.Center });
        return result;
    }

    private static Border RoundedImage(FrameworkElement image, double radius)
    {
        var container = new Border { Child = image, CornerRadius = new CornerRadius(radius) };
        container.SizeChanged += (_, _) => container.Clip = new RectangleGeometry(new Rect(container.RenderSize), radius, radius);
        return container;
    }

    private const string ButtonStyle = """
        <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="Button">
                <Border x:Name="plate" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                  CornerRadius="9" Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                  <ContentPresenter VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                    HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" RecognizesAccessKey="True"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="plate" Property="Opacity" Value=".83"/></Trigger>
                  <Trigger Property="IsPressed" Value="True"><Setter TargetName="plate" Property="Opacity" Value=".65"/></Trigger>
                  <Trigger Property="IsEnabled" Value="False"><Setter TargetName="plate" Property="Opacity" Value=".44"/></Trigger>
                  <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter TargetName="plate" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"
                      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"/>
                    <Setter TargetName="plate" Property="BorderThickness" Value="2"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Style>
        """;

    private const string SwitchStyle = """
        <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="CheckBox">
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="CheckBox">
                <Grid Background="Transparent">
                  <Border x:Name="track" Width="38" Height="22" CornerRadius="11"
                    Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
                    <Ellipse x:Name="knob" Width="16" Height="16" Fill="White" Margin="2" HorizontalAlignment="Left"/>
                  </Border>
                </Grid>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsChecked" Value="True">
                    <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                    <Setter TargetName="track" Property="Background" Value="{Binding Foreground, RelativeSource={RelativeSource TemplatedParent}}"/>
                  </Trigger>
                  <Trigger Property="IsEnabled" Value="False"><Setter TargetName="track" Property="Opacity" Value=".5"/></Trigger>
                  <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"/>
                    <Setter TargetName="track" Property="BorderThickness" Value="2"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Style>
        """;
}

internal sealed class SampleWeather : FrameworkElement
{
    private readonly DesktopController desktop;
    private readonly DispatcherTimer timer;
    private readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();

    public SampleWeather(DesktopController desktop)
    {
        this.desktop = desktop;
        timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(48) };
        timer.Tick += (_, _) => InvalidateVisual();
        Loaded += (_, _) => timer.Start();
        Unloaded += (_, _) => timer.Stop();
    }

    protected override void OnRender(DrawingContext context)
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var image = Artwork.Image((Wallpaper.Find(desktop.Options.Wallpaper) ?? Wallpaper.Find(Wallpaper.Cabin)!).Resource, 480);
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        double zoom = Math.Max(ActualWidth / image.PixelWidth, ActualHeight / image.PixelHeight);
        double width = image.PixelWidth * zoom, height = image.PixelHeight * zoom;
        context.PushClip(new RectangleGeometry(bounds));
        context.DrawImage(image, new Rect((ActualWidth - width) / 2, (ActualHeight - height) / 2, width, height));
        var random = new Random(18613);
        double time = desktop.Options.Snow && SystemParameters.ClientAreaAnimation ? clock.Elapsed.TotalSeconds : 1;
        for (int i = 0; i < 25 + desktop.Options.Density * 70; i++)
        {
            double x = (random.NextDouble() * ActualWidth + desktop.Options.Wind * time * 20) % ActualWidth;
            if (x < 0) x += ActualWidth;
            double y = (random.NextDouble() * ActualHeight + time * (8 + random.NextDouble() * 30) * (.5 + desktop.Options.Speed)) % ActualHeight;
            double radius = .55 + random.NextDouble() * 1.55;
            context.DrawEllipse(SnowArt.Ink(0xC2FFFFFF), null, new Point(x, y), radius, radius);
        }
        context.Pop();
    }
}
