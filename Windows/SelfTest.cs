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

            Write(report, $"PASS {RuntimeInformation.ProcessArchitecture}: 4 settings pages, 12 wallpapers, 32 icons, ornament assets, scene round trip, window snow physics, corner overflow and redeposition, snowfall pause and resume, and Windows wallpaper API ({displays} display paths).");
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
        CheckNaturalWindowOverflow(monitor);
        CheckSnowPause(monitor);
        var options = new SnowOptions { Snowballs = 2, AutomaticPlow = false };
        var person = new Snowperson(new(460, 350), true, SnowmanOutfit.Santa);
        person.ApplyClothes(options, snow.FloorY);
        person.FallFromWindow();
        var previous = person.Balls[0].Center.Y;
        person.Step(.05f, monitor.Width, snow.FloorY, false);
        Require(person.Tumbled && person.Balls.Count == 2 && person.Balls[0].Center.Y > previous, "Snowman falls from a window");
    }

    private static void CheckNaturalWindowOverflow(MonitorInfo monitor)
    {
        var options = new SnowOptions { Density = 0, AutomaticPlow = false };
        var upper = new WindowSample(13, new Box(240, 130, 640, 350), false, 8, "Upper");
        var lower = new WindowSample(14, new Box(80, 380, 470, 560), false, 8, "Lower");
        var thin = new SnowPack(400, false);
        thin.Land(9, 8);
        Require(thin.SpillFromCorner(true, 0) == 0, "Thin snowfall stays on the sill");

        foreach (bool caught in new[] { true, false })
        {
            var snow = new SnowScene(monitor);
            var samples = caught ? new[] { upper, lower } : new[] { upper };
            snow.SetDesktop(samples, 1, .08f, true);
            Shelf bank = snow.Shelves.First();
            bank.Snow.DepositClump(3, 43);
            float before = Mass(bank.Snow);
            for (int i = 0; i < 14; i++) snow.Step(.016f, options, true, false, null, null);
            var first = snow.Grains.Single(grain => grain.Slide is not null);
            Require(first.Slide!.Rolling && first.Position.X > bank.Frame.Left, "Clump rolls out along the corner");
            Require(Math.Abs(Mass(bank.Snow) + first.Mass - before) < .001f && bank.Snow.Level(0) > 0, "Overflow removes only the lost edge snow");
            snow.SetDesktop(caught ? [upper with { Frame = new Box(254, 130, 654, 350) }, lower] :
                [upper with { Frame = new Box(254, 130, 654, 350) }], 2, .08f, true);
            snow.Step(.016f, options, true, false, null, null);
            Require(snow.Grains.Single().Position.X > first.Position.X + 10, "Corner overflow follows its moving window");
            for (int i = 0; i < 120; i++) snow.Step(.016f, options, true, false, null, null);
            Shelf landing = caught ? snow.Shelves[1] : snow.Shelves.Last();
            Require(snow.Grains.Count == 0 && Math.Abs(Mass(landing.Snow) - first.Mass) < .001f, "Clump adds its mass to the first surface below");
            if (caught) Require(Mass(snow.Shelves.Last().Snow) == 0, "A lower window intercepts the spill before it reaches the floor");
        }

        var masked = new SnowScene(monitor);
        var cover = new WindowSample(15, new Box(180, 134, 270, 270), false, 8, "Cover");
        masked.SetDesktop([cover, upper], 1, .08f, true);
        Shelf hiddenEdge = masked.Shelves.First(shelf => shelf.Frame.Left == upper.Frame.Left);
        hiddenEdge.Snow.DepositClump(3, 43);
        for (int i = 0; i < 30; i++) masked.Step(.016f, options, true, false, null, null);
        Require(masked.Grains.Count == 0, "Foreground window blocks the corner's roll path");

        static float Mass(SnowPack pack) => Enumerable.Range(0, pack.Count).Sum(pack.Level);
    }

    private static void CheckSnowPause(MonitorInfo monitor)
    {
        var scene = new SnowScene(monitor);
        var options = new SnowOptions { AutomaticPlow = false };
        var window = new WindowSample(16, new Box(180, 180, 620, 450), false, 8, "Window");
        scene.SetDesktop([window], 1, .08f, true);
        Shelf floor = scene.Shelves.Last();
        floor.Snow.DepositClump(360, 20);
        scene.Step(.016f, options, true, false, null, null);
        Flake original = scene.Flakes.Where(flake => flake.Position.Y > 40 && flake.Position.Y < 100).First();
        int count = scene.Flakes.Count;
        float floorMass = Mass(floor.Snow);
        scene.Step(.016f, options, false, false, null, null);
        Require(scene.Flakes.Count <= count && scene.Flakes.Single(flake => flake.Phase == original.Phase).Position.Y > original.Position.Y,
            "Pausing keeps visible flakes in motion without spawning");
        for (int step = 0; step < 1800 && scene.Flakes.Count > 0; step++)
        {
            count = scene.Flakes.Count;
            scene.Step(.025f, options, false, false, null, null);
            Require(scene.Flakes.Count <= count, "No new snowflakes appear while paused");
        }
        Require(scene.Flakes.Count == 0 && Mass(floor.Snow) > floorMass, "Airborne snow settles on the preserved snowpack");
        float retained = Mass(floor.Snow);
        for (int step = 0; step < 30; step++) scene.Step(.025f, options, false, false, null, null);
        Require(Mass(floor.Snow) == retained, "Paused snow remains after all flakes land");
        scene.Step(.001f, options, true, false, null, null);
        Require(scene.Flakes.Count > 0 && scene.Flakes.All(flake => flake.Position.Y < 0), "Resumed flakes arrive from above");
        scene.ClearSnow();
        Require(Mass(floor.Snow) == 0, "Clearing snow is independent of pausing");

        static float Mass(SnowPack pack) => Enumerable.Range(0, pack.Count).Sum(pack.Level);
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
