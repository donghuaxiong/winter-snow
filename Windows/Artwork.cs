using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;

namespace Snowglow.Windows;

internal sealed record Wallpaper(string Key, string Name, bool Christmas)
{
    public const string Cabin = "cabin";
    public static readonly Wallpaper[] All =
    [
        new("reindeer-lanterns", "林间鹿影", true), new("santa-rooftop", "圣诞夜来客", true),
        new("christmas-square", "雪镇圣诞树", true), new("sleigh-under-stars", "星夜归途", true),
        new(Cabin, "雪夜木屋", false), new("alpine-dawn", "雪岭晨曦", false),
        new("frost-lake", "雪后镜湖", false), new("birch-hush", "白桦静雪", false),
        new("frost-coast", "雪岸潮声", false), new("snow-village", "雪町灯火", false),
        new("north-lights", "北境极光", false), new("moon-cedars", "月照雪松", false)
    ];

    public string Resource => Key == Cabin ? "WinterCabin.jpg" : $"Wallpapers.{Key}.jpg";
    public static Wallpaper? Find(string? key) => All.FirstOrDefault(item => item.Key == key);
}

internal static class Artwork
{
    private static readonly Dictionary<(string Resource, int Width), BitmapSource> Images = new();

    internal static Stream Open(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
        ?? throw new FileNotFoundException("Resource: " + name);

    internal static BitmapSource Image(string name, int width = 0)
    {
        if (Images.TryGetValue((name, width), out var cached)) return cached;
        using Stream stream = Open(name);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.DecodePixelWidth = width;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        Images.Add((name, width), image);
        return image;
    }

    internal static BitmapSource Icon(string key) => Image($"Icons.{key}.png", 96);
}

internal static class DesktopWallpaperService
{
    private static readonly Guid ClassId = new("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD");
    private const int Fill = 4;

    internal static int Probe()
    {
        using var client = new Client();
        client.Native.GetMonitorDevicePathCount(out uint count);
        client.Native.GetPosition(out _);
        for (uint index = 0; index < count; index++)
        {
            client.Native.GetMonitorDevicePathAt(index, out string key);
            client.Native.GetWallpaper(key, out _);
        }
        return (int)count;
    }

    internal static string Apply(Settings settings, Wallpaper wallpaper)
    {
        string folder = Path.Combine(Settings.Folder, "Wallpapers");
        Directory.CreateDirectory(folder);
        string file = Path.Combine(folder, wallpaper.Key + ".jpg");
        if (!File.Exists(file))
        {
            using Stream artwork = Artwork.Open(wallpaper.Resource);
            using (var staging = File.Create(file + ".tmp")) artwork.CopyTo(staging);
            File.Move(file + ".tmp", file, overwrite: true);
        }

        using var client = new Client();
        if (settings.PreviousBackground is null)
        {
            client.Native.GetMonitorDevicePathCount(out uint count);
            var paths = new Dictionary<string, string>();
            for (uint i = 0; i < count; i++)
            {
                client.Native.GetMonitorDevicePathAt(i, out string id);
                client.Native.GetWallpaper(id, out string path);
                paths[id] = path;
            }
            client.Native.GetBackgroundColor(out uint color);
            client.Native.GetPosition(out int position);
            settings.PreviousBackground = new(paths, color, position);
            settings.Save();
        }
        client.Native.SetWallpaper(null, file);
        settings.Wallpaper = wallpaper.Key;
        settings.Save();
        client.Native.SetPosition(Fill);
        return $"已设为壁纸 · {wallpaper.Name}";
    }

    internal static string Restore(Settings settings)
    {
        if (settings.PreviousBackground is not { } previous) return "未找到可恢复的原壁纸。";
        using var client = new Client();
        client.Native.SetBackgroundColor(previous.Color);
        client.Native.SetPosition(previous.Position);
        int restored = 0;
        foreach (var (display, path) in previous.Images.ToArray())
        {
            try
            {
                client.Native.SetWallpaper(display, string.IsNullOrEmpty(path) ? null : path);
                previous.Images.Remove(display);
                restored++;
            }
            catch (COMException) { /* Retain disconnected displays for a later retry. */ }
        }
        if (previous.Images.Count == 0)
        {
            settings.PreviousBackground = null;
            settings.Wallpaper = null;
        }
        settings.Save();
        return settings.PreviousBackground is null ? "已恢复原壁纸。"
            : $"已恢复 {restored} 台显示器；其余显示器连接后可重试。";
    }

    private sealed class Client : IDisposable
    {
        internal readonly IDesktopWallpaper Native = (IDesktopWallpaper)Activator.CreateInstance(Type.GetTypeFromCLSID(ClassId, true)!)!;
        public void Dispose() => Marshal.FinalReleaseComObject(Native);
    }

    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitor, [MarshalAs(UnmanagedType.LPWStr)] string? path);
        void GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor, [MarshalAs(UnmanagedType.LPWStr)] out string path);
        void GetMonitorDevicePathAt(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetMonitorDevicePathCount(out uint count);
        void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitor, out MonitorRectangle rectangle);
        void SetBackgroundColor(uint color);
        void GetBackgroundColor(out uint color);
        void SetPosition(int position);
        void GetPosition(out int position);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorRectangle { public int Left, Top, Right, Bottom; }
}
