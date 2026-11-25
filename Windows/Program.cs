using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Tray = System.Windows.Forms;

namespace Snowglow.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] arguments)
    {
        if (arguments.Length > 0 && arguments[0] == "--self-test")
            return SelfTest.Run(arguments.Length > 1 ? arguments[1] : null, arguments.Length > 2 ? arguments[2] : null);

        using var singleton = new Mutex(true, @"Local\Snowglow.Windows", out bool first);
        using var wake = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Snowglow.Windows.Settings");
        if (!first)
        {
            wake.Set();
            return 0;
        }

        NativeDesktop.EnablePerMonitorDpi();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.DispatcherUnhandledException += (_, error) =>
        {
            StartupError(error.Exception);
            error.Handled = true;
            app.Shutdown(1);
        };

        try
        {
            using var desktop = new DesktopController(Settings.Load());
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Snowglow.ico")!;
            using var icon = new Icon(stream, System.Windows.Forms.SystemInformation.SmallIconSize);
            using var menu = new Tray.ContextMenuStrip();
            using var tray = new Tray.NotifyIcon
            {
                Icon = icon, Text = "Snowglow 雪灯桌面", ContextMenuStrip = menu, Visible = true
            };

            ControlPanel? panel = null;
            void ShowSettings()
            {
                if (panel is null)
                {
                    panel = new ControlPanel(desktop);
                    desktop.SettingsWindow = panel;
                    panel.Closed += (_, _) => { panel = null; desktop.SettingsWindow = null; };
                    panel.Show();
                }
                if (panel.WindowState == WindowState.Minimized) panel.WindowState = WindowState.Normal;
                panel.Activate();
            }

            menu.Items.Add("打开设置", null, (_, _) => ShowSettings());
            var snowfall = new Tray.ToolStripMenuItem("飘雪", null, (_, _) =>
            {
                desktop.Options.Snow = !desktop.Options.Snow;
                desktop.Apply();
            });
            menu.Items.Add(snowfall);
            menu.Items.Add(new Tray.ToolStripSeparator());
            var snowman = new Tray.ToolStripMenuItem("", null, (_, _) => desktop.AddOrResetSnowman());
            menu.Items.Add(snowman);
            menu.Items.Add("立即铲雪", null, (_, _) => desktop.PlowNow());
            menu.Items.Add("清空积雪", null, (_, _) => desktop.ClearSnow());
            menu.Items.Add("预览降雪", null, (_, _) => desktop.Preview());
            menu.Items.Add("应用雪夜木屋", null, (_, _) => desktop.ApplyCabin());
            menu.Items.Add(new Tray.ToolStripSeparator());
            menu.Items.Add("退出 Snowglow", null, (_, _) => app.Shutdown());
            menu.Opening += (_, _) =>
            {
                snowfall.Checked = desktop.Options.Snow;
                snowman.Text = desktop.Options.ShowSnowman ? "把雪人移到底边" : "添加雪人";
            };
            tray.MouseClick += (_, e) => { if (e.Button == Tray.MouseButtons.Left) ShowSettings(); };
            var registration = ThreadPool.RegisterWaitForSingleObject(wake,
                (_, _) => app.Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(ShowSettings)), null, Timeout.Infinite, false);
            try
            {
                app.Startup += (_, _) => ShowSettings();
                return app.Run();
            }
            finally
            {
                registration.Unregister(null);
                tray.Visible = false;
            }
        }
        catch (Exception error)
        {
            StartupError(error);
            return 1;
        }
    }

    private static void StartupError(Exception error)
    {
        string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Snowglow");
        string file = Path.Combine(folder, "error.log");
        try
        {
            Directory.CreateDirectory(folder);
            File.WriteAllText(file, error.ToString());
        }
        catch (Exception io) when (io is IOException or UnauthorizedAccessException) { }
        MessageBox.Show("Snowglow 遇到错误。详细信息记录在 %LOCALAPPDATA%\\Snowglow\\error.log。\n\n" + error.Message,
            "Snowglow", MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
