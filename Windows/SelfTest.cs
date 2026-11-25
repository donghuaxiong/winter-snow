using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;

namespace Snowglow.Windows;

internal static class SelfTest
{
    public static int Run(string? report, string? preview)
    {
        try
        {
            var original = JsonSerializer.Deserialize<Settings>("""{"Snow":false,"Outfit":1,"Density":0.58}""")!;
            original.Normalize();
            Require(!original.Snow && original.Outfit == SnowmanOutfit.Santa && original.Icicles, "Legacy settings");

            var item = new Decoration(Guid.NewGuid(), DecorationKind.Tree, "Display", .5f, .7f);
            original.Decorations.Add(item);
            original.Wallpaper = Wallpaper.Cabin;
            original.Scenes.Add(new SavedScene(Guid.NewGuid(), "冬景", original.Snapshot()));
            var restored = JsonSerializer.Deserialize<Settings>(JsonSerializer.Serialize(original))!;
            restored.Decorations.Clear();
            var snapshot = restored.WithScene(restored.Scenes[0].Options);
            Require(snapshot.Decorations.Single() == item && snapshot.Wallpaper == Wallpaper.Cabin, "Scene settings");
            Require(!ReferenceEquals(snapshot.Decorations, restored.Scenes[0].Options.Decorations), "Scene isolation");

            Require(Wallpaper.All.Length == 12 && Wallpaper.All.Count(art => art.Christmas) == 4, "Wallpaper list");
            foreach (Wallpaper wallpaper in Wallpaper.All)
            {
                var image = Artwork.Image(wallpaper.Resource);
                Require(image.PixelWidth == 1672 && image.PixelHeight == 941, wallpaper.Name);
            }
            var iconNames = Assembly.GetExecutingAssembly().GetManifestResourceNames()
                .Where(name => name.StartsWith("Icons.", StringComparison.Ordinal)).ToArray();
            Require(iconNames.Length == 32, "Icon list");
            foreach (string name in iconNames) Require(Artwork.Image(name).PixelWidth == 128, name);
            foreach (DecorationKind kind in Enum.GetValues<DecorationKind>().Where(kind => kind != DecorationKind.Lights))
                Require(Artwork.Image($"Decorations.{DecorationArt.Key(kind)}.png").PixelWidth > 0, kind.ToString());
            int displays = DesktopWallpaperService.Probe();
            CheckPhysics();

            using var desktop = new DesktopController(original, live: false);
            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var panel = new ControlPanel(desktop);
            panel.ValidatePages(preview);
            panel.Close();
            application.Shutdown();

            Write(report, $"PASS {RuntimeInformation.ProcessArchitecture}: 4 settings pages, 12 wallpapers, 32 icons, ornament assets, scene round trip, window snow physics, and Windows wallpaper API ({displays} display paths).");
            return 0;
        }
        catch (Exception error)
        {
            Write(report, error.ToString());
            return 1;
        }
    }

    private static void CheckPhysics()
    {
        var monitor = new MonitorInfo("Test", new Box(0, 0, 1280, 720), 1, true);
        var snow = new SnowScene(monitor);
        var sample = new WindowSample(12, new Box(160, 140, 650, 410), false, 8, "Test");
        snow.SetDesktop([sample], 1, .08f, true);
        var bank = snow.Shelves.Single(shelf => !shelf.IsFloor);
        for (int x = 24; x < 450; x += 15) bank.Snow.Land(x, 20);
        snow.SetDesktop([sample with { Frame = new Box(178, 140, 668, 410) }], 2, .08f, true);
        Require(snow.Shelves.Contains(bank) && bank.Frame.Left == 178, "Snow bank follows its window");
        snow.SetDesktop([], 3, .08f, true);
        Require(snow.Grains.Count > 0, "Window snow sheds after minimization");
        var options = new SnowOptions { Snowballs = 2, AutomaticPlow = false };
        var person = new Snowperson(new(460, 350), true, SnowmanOutfit.Santa);
        person.ApplyClothes(options, snow.FloorY);
        person.FallFromWindow();
        var previous = person.Balls[0].Center.Y;
        person.Step(.05f, monitor.Width, snow.FloorY, false);
        Require(person.Tumbled && person.Balls.Count == 2 && person.Balls[0].Center.Y > previous, "Snowman falls from a window");
    }

    private static void Require(bool result, string check)
    {
        if (!result) throw new InvalidOperationException(check);
    }

    private static void Write(string? path, string message)
    {
        if (path is not null) File.WriteAllText(path, message);
        else Console.WriteLine(message);
    }
}
