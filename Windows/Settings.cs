using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Snowglow.Windows;

internal sealed record SnowmanPlacement(string Monitor, float X, float? Y, string? Window = null);
internal enum SnowLayer { BehindWindows, BehindFrontWindow, InFront }
internal enum DecorationKind { Tree, Lights, Lantern, Gift, Calendar }
internal sealed record Decoration(Guid Id, DecorationKind Kind, string Monitor, float X, float Y,
    float Scale = 1, float Rotation = 0, string? Window = null, int Opened = 0, int Palette = 0, int LightEffect = 1);
internal sealed record SavedScene(Guid Id, string Name, SnowOptions Options);
internal sealed record DesktopBackground(Dictionary<string, string> Images, uint Color, int Position);

internal record SnowOptions
{
    public bool Snow { get; set; } = true;
    public bool Accumulation { get; set; } = true;
    public bool AutomaticPlow { get; set; } = true;
    public bool PlowCollision { get; set; }
    public bool Icicles { get; set; } = true;
    public bool ShowSnowman { get; set; } = true;
    public float Density { get; set; } = .58f;
    public float Speed { get; set; } = .55f;
    public float Wind { get; set; } = .10f;
    public int IdleSeconds { get; set; }
    public bool OnlyIdle { get; set; }
    public bool IdleDim { get; set; } = true;
    public SnowLayer Layer { get; set; } = SnowLayer.BehindWindows;
    public SnowmanOutfit Outfit { get; set; } = SnowmanOutfit.Santa;
    public SnowmanFace Face { get; set; }
    public SnowmanScarf Scarf { get; set; }
    public int Snowballs { get; set; } = 3;
    public bool Arms { get; set; } = true;
    public bool Buttons { get; set; } = true;
    public SnowmanPlacement? Placement { get; set; }
    public bool ShowDecorations { get; set; } = true;
    public List<Decoration> Decorations { get; set; } = [];
    public string? Wallpaper { get; set; }

    public SnowOptions Snapshot() => new SnowOptions(this) { Decorations = [.. Decorations] };

    public void Normalize()
    {
        Density = Math.Clamp(Density, 0, 1);
        Speed = Math.Clamp(Speed, 0, 1);
        Wind = Math.Clamp(Wind, -1, 1);
        if (!Enum.IsDefined(Layer)) Layer = SnowLayer.BehindWindows;
        if (!Enum.IsDefined(Outfit)) Outfit = SnowmanOutfit.Santa;
        if (!Enum.IsDefined(Face)) Face = SnowmanFace.Smile;
        if (!Enum.IsDefined(Scarf)) Scarf = SnowmanScarf.Auto;
        if (Snowballs is not (2 or 3)) Snowballs = 3;
        if (IdleSeconds is not (0 or 30 or 60 or 120 or 300 or 600)) IdleSeconds = 0;
        if (IdleSeconds == 0) OnlyIdle = false;
        if (Placement is { } pose && (!float.IsFinite(pose.X) || pose.Y is { } y && !float.IsFinite(y)))
            Placement = null;
        Decorations = (Decorations ?? []).Where(d => d is not null && Enum.IsDefined(d.Kind) &&
            float.IsFinite(d.X) && float.IsFinite(d.Y) && float.IsFinite(d.Scale) && float.IsFinite(d.Rotation))
            .Select(d => d with { X = Math.Clamp(d.X, 0, 1), Y = Math.Clamp(d.Y, 0, 1), Scale = Math.Clamp(d.Scale, .5f, 2) })
            .DistinctBy(d => d.Id).ToList();
    }
}

internal sealed record Settings : SnowOptions
{
    internal static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Snowglow");
    private static readonly string SettingsFile = Path.Combine(Folder, "settings.json");
    public List<SavedScene> Scenes { get; set; } = [];
    public DesktopBackground? PreviousBackground { get; set; }

    public Settings() { }
    private Settings(SnowOptions source) : base(source.Snapshot()) { }

    public Settings WithScene(SnowOptions source) => new(source)
    {
        Scenes = Scenes,
        PreviousBackground = PreviousBackground
    };

    public static Settings Load()
    {
        try
        {
            if (!File.Exists(SettingsFile)) return new Settings();
            var result = JsonSerializer.Deserialize<Settings>(File.ReadAllBytes(SettingsFile)) ?? new Settings();
            result.Normalize();
            result.Scenes = (result.Scenes ?? []).Where(scene => scene is not null && scene.Options is not null).ToList();
            foreach (var scene in result.Scenes) scene.Options.Normalize();
            return result;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            Trace.TraceWarning(error.Message);
            return new Settings();
        }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            string staging = SettingsFile + ".tmp";
            File.WriteAllBytes(staging, JsonSerializer.SerializeToUtf8Bytes(this));
            File.Move(staging, SettingsFile, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Trace.TraceWarning(error.Message);
        }
    }
}
