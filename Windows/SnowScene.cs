using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;

namespace Snowglow.Windows;

internal struct Flake
{
    public Vector2 Position;
    public float Radius, Speed, Phase, Opacity;
}

internal struct SnowGrain
{
    public Vector2 Position, Velocity;
    public float Radius, Mass, Life;
}

internal sealed class SnowScene
{
    private readonly Random random;
    private readonly Dictionary<nint, Shelf> windows = [];
    private readonly List<Shelf> shelves = [];
    private readonly List<Flake> flakes = [];
    private readonly List<SnowGrain> grains = [];
    private readonly List<PushedSnowperson> wrecks = [];
    private readonly Shelf floor;
    private int nextPlowDirection = 1;
    private float settleClock, cooldown, weatherTime;
    private float powderLoad, ambientClock;
    private readonly Box viewport;

    public MonitorInfo Monitor { get; }
    public Box? Taskbar { get; private set; }
    public Box? SettingsCover { get; set; }
    public float FloorY => floor.Frame.Top;
    public PlowPass? Plow { get; private set; }
    public float PlowLoad => powderLoad;
    public Snowperson? Person { get; set; }
    public IReadOnlyList<Shelf> Shelves => shelves;
    public IReadOnlyList<Flake> Flakes => flakes;
    public IReadOnlyList<SnowGrain> Grains => grains;
    public IReadOnlyList<PushedSnowperson> Wrecks => wrecks;
    public List<Box> FlakeCovers { get; } = [];
    public List<PlacedDecoration> Decorations { get; } = [];
    public bool ShowIcicles { get; private set; }

    public SnowScene(MonitorInfo monitor)
    {
        Monitor = monitor;
        random = new Random(StringComparer.Ordinal.GetHashCode(monitor.Name));
        viewport = new Box(0, 0, monitor.Width, monitor.Height);
        floor = new Shelf(new Box(0, monitor.Height - 1, monitor.Width, monitor.Height + 1), true);
        shelves.Add(floor);
    }

    public void SetDesktop(IReadOnlyList<WindowSample> samples, double now, float elapsed, bool collectSnow)
    {
        Taskbar = null;
        float floorY = Monitor.Height - 1;
        foreach (WindowSample window in samples)
        {
            if (!window.Taskbar) continue;
            Box overlap = Monitor.ToLocal(window.Frame).Intersect(viewport);
            if (!overlap.HasArea || Math.Min(overlap.Width, overlap.Height) < 9) continue;
            Taskbar = overlap;
            if (overlap.Bottom >= viewport.Bottom - 3 && overlap.Width >= viewport.Width * .70f)
                floorY = Math.Max(1, overlap.Top);
            break;
        }
        floor.Frame = new Box(0, floorY, Monitor.Width, floorY + 1);
        var nearer = new List<Box>();
        var seen = new HashSet<nint>();
        shelves.Clear();
        foreach (WindowSample window in samples)
        {
            Box frame = Monitor.ToLocal(window.Frame);
            if (!frame.Intersect(viewport).HasArea) continue;
            if (!window.Taskbar && frame.Width > 95 && frame.Height > 55 && frame.Top >= -1 && frame.Top < floorY - 2)
            {
                seen.Add(window.Handle);
                if (!windows.TryGetValue(window.Handle, out Shelf? shelf))
                {
                    shelf = new Shelf(frame, false);
                    windows.Add(window.Handle, shelf);
                }

                float velocity = (frame.Left - shelf.Frame.Left) / Math.Max(.025f, elapsed);
                if (collectSnow && now - shelf.LastShake > .35 && Math.Abs(velocity) > 420
                    && Math.Abs(shelf.LastVelocity) > 330 && Math.Sign(velocity) != Math.Sign(shelf.LastVelocity)
                    && Math.Abs(frame.Width - shelf.Frame.Width) < 16)
                {
                    Shed(shelf, velocity * .25f, .60f);
                    shelf.LastShake = now;
                }
                shelf.LastVelocity = velocity;
                shelf.Frame = frame;
                shelf.Radius = frame.Width >= viewport.Width && frame.Top <= 1 ? 0 : window.CornerRadius;
                List<Span> visible = Shelf.Exposed(frame, viewport, nearer);
                if (!shelf.Visible.SequenceEqual(visible)) shelf.Visible = visible;
                shelf.Snow.Resize(frame.Width);
                if (shelf.Visible.Count > 0) shelves.Add(shelf);
            }
            if (!window.Taskbar) nearer.Add(frame);
        }

        foreach (nint handle in new List<nint>(windows.Keys))
        {
            if (seen.Contains(handle)) continue;
            if (windows.Remove(handle, out Shelf? shelf) && collectSnow)
                Shed(shelf, shelf.LastVelocity * .12f, 1);
        }
        shelves.Sort((left, right) => left.Frame.Top.CompareTo(right.Frame.Top));
        shelves.Add(floor);
        Person?.Pose(floorY);
    }

    private void Shed(Shelf shelf, float velocity, float fraction)
    {
        foreach (Span span in shelf.Visible)
        {
            float step = Math.Max(9, span.Length / 54);
            for (float x = span.Left + step / 2; x < span.Right; x += step)
            {
                float local = x - shelf.Frame.Left;
                float height = shelf.Snow.At(local);
                if (height < .45f) continue;
                float level = height * (1 - fraction);
                float removed = shelf.Snow.RemoveInSpan(local - step / 2, local + step / 2 - .01f, level);
                if (removed <= .03f) continue;
                AddGrain(new SnowGrain
                {
                    Position = new Vector2(x, shelf.TopAt(x) - height * .7f),
                    Velocity = new Vector2(velocity + Range(-35, 35), Range(-16, 45)),
                    Radius = Math.Clamp(height * .50f, 2, 8),
                    Mass = removed * .95f,
                    Life = 7
                });
            }
        }
    }

    public bool StartPlow()
    {
        if (Plow is not null) return false;
        Plow = new PlowPass(Monitor.Width, nextPlowDirection);
        nextPlowDirection *= -1;
        powderLoad = 0;
        return true;
    }

    public void ClearSnow()
    {
        floor.Snow.Clear();
        foreach (Shelf shelf in windows.Values) shelf.Snow.Clear();
        grains.Clear();
        Plow = null;
        powderLoad = 0;
        cooldown = 1;
    }

    public void Step(float delta, SnowOptions options, bool snowing, bool reducedMotion, Vector2? previousMouse, Vector2? mouse)
    {
        ShowIcicles = options.Icicles && options.Accumulation;
        if (snowing)
        {
            weatherTime += delta;
            FlyFlakes(delta, options, reducedMotion);
            if (options.Accumulation)
            {
                ambientClock += delta;
                if (options.Density > 0 && ambientClock >= .07f)
                {
                    ambientClock -= .07f;
                    int samples = Math.Clamp((int)(Monitor.Width / 510), 1, 6);
                    for (int i = 0; i < samples; i++)
                        floor.Snow.Land(Range(0, Monitor.Width), (.85f + options.Density * 1.7f) * (reducedMotion ? 1.1f : 1));
                }
                else if (options.Density == 0) ambientClock = 0;
                if (previousMouse is { } from && mouse is { } to && !reducedMotion)
                    Sweep(from, to, delta);
            }
        }

        if (options.Accumulation)
        {
            settleClock += delta;
            if (settleClock > .18f)
            {
                settleClock = 0;
                foreach (Shelf shelf in shelves) shelf.Snow.Settle();
            }

            if (cooldown > 0) cooldown -= delta;
            if (snowing && options.AutomaticPlow && cooldown <= 0 && Plow is null && floor.Snow.DeepEnough)
                StartPlow();
        }

        Person?.Step(delta, Monitor.Width, FloorY, reducedMotion);
        StepGrains(delta, options.Accumulation);
        if (Plow is { } pass)
        {
            StepPlow(delta, pass, reducedMotion);
            if (options.PlowCollision && Person is { Dragging: false } snowman && PlowHits(pass, snowman))
            {
                wrecks.Add(new PushedSnowperson(snowman, pass));
                Person = null;
                options.ShowSnowman = false;
                options.Placement = null;
            }
            if (pass.Finished(Monitor.Width))
            {
                Plow = null;
                cooldown = 7;
            }
        }
        for (int i = wrecks.Count - 1; i >= 0; i--)
            if (!wrecks[i].Step(delta, Plow, Monitor.Width, FloorY, reducedMotion))
                wrecks.RemoveAt(i);
    }

    private bool PlowHits(PlowPass pass, Snowperson snowman)
    {
        foreach (Snowball ball in snowman.Balls)
            if (pass.Hits(ball, FloorY))
                return true;
        return false;
    }

    private void FlyFlakes(float delta, SnowOptions options, bool reducedMotion)
    {
        int target = (int)Math.Clamp(Monitor.Width * Monitor.Height / 4400 * options.Density * 1.70f, 0, 730);
        if (reducedMotion) target /= 3;
        while (flakes.Count < target) flakes.Add(NewFlake(scattered: true));
        if (flakes.Count > target) flakes.RemoveRange(target, flakes.Count - target);

        for (int i = 0; i < flakes.Count; i++)
        {
            Flake flake = flakes[i];
            Vector2 old = flake.Position;
            float sway = reducedMotion ? 0 : 14 * MathF.Sin(weatherTime * .84f + flake.Phase);
            flake.Position += new Vector2((options.Wind * 56 + sway) * delta, flake.Speed * (.30f + options.Speed * 1.25f) * delta);
            if (flake.Position.X < -8) flake.Position.X += Monitor.Width + 16;
            if (flake.Position.X > Monitor.Width + 8) flake.Position.X -= Monitor.Width + 16;
            if (options.Accumulation && FindLanding(old.Y, flake.Position, out Shelf? shelf))
            {
                shelf!.Snow.Land(flake.Position.X - shelf.Frame.Left, .36f + .65f * flake.Radius);
                flake = NewFlake(scattered: false);
            }
            else if (flake.Position.Y > FloorY + 8) flake = NewFlake(scattered: false);
            flakes[i] = flake;
        }
    }

    private Flake NewFlake(bool scattered)
    {
        float depth = Unit();
        return new Flake
        {
            Position = new Vector2(Range(0, Monitor.Width), scattered ? Range(-4, FloorY) : Range(-70, -3)),
            Radius = .75f + depth * depth * 2.05f,
            Speed = 29 + depth * 57,
            Opacity = .26f + .56f * depth,
            Phase = Range(0, 6.283f)
        };
    }

    private bool FindLanding(float oldY, Vector2 point, out Shelf? support)
    {
        float lowestY = float.MaxValue;
        support = null;
        foreach (Shelf shelf in shelves)
        {
            if (shelf.Frame.Top - 25 > point.Y || !shelf.Supports(point.X)) continue;
            float snowTop = shelf.TopAt(point.X) - shelf.Snow.At(point.X - shelf.Frame.Left);
            if (oldY > snowTop + 2 || point.Y < snowTop || snowTop >= lowestY) continue;
            lowestY = snowTop;
            support = shelf;
        }
        return support is not null;
    }

    private void StepGrains(float delta, bool collect)
    {
        for (int i = grains.Count - 1; i >= 0; i--)
        {
            SnowGrain grain = grains[i];
            float oldY = grain.Position.Y;
            grain.Velocity.Y += 570 * delta;
            grain.Position += grain.Velocity * delta;
            grain.Life -= delta;
            if (collect && grain.Velocity.Y >= 0 && grain.Mass > 0 &&
                FindLanding(oldY + grain.Radius * .6f, grain.Position + new Vector2(0, grain.Radius * .6f), out Shelf? landing))
            {
                landing!.Snow.Land(grain.Position.X - landing.Frame.Left, grain.Mass);
                grains.RemoveAt(i);
            }
            else if (grain.Position.Y > FloorY + 12 || grain.Position.X < -50 || grain.Position.X > Monitor.Width + 50 || grain.Life <= 0)
                grains.RemoveAt(i);
            else grains[i] = grain;
        }
    }

    private void Sweep(Vector2 from, Vector2 to, float delta)
    {
        Vector2 movement = to - from;
        float size = movement.Length();
        if (size < 3 || size > 270) return;
        float velocity = movement.X / delta;
        int steps = Math.Clamp((int)(size / 8), 1, 14);
        for (int step = 1; step <= steps; step++)
        {
            var pointer = Vector2.Lerp(from, to, (float)step / steps);
            if (SettingsCover is { } cover && cover.Contains(pointer)) continue;
            foreach (Shelf shelf in shelves)
            {
                if (!shelf.Supports(pointer.X)) continue;
                float x = pointer.X - shelf.Frame.Left;
                float height = shelf.Snow.At(x);
                float roof = shelf.TopAt(pointer.X);
                float snowTop = roof - height;
                if (height < .18f || pointer.Y > roof + 3 || pointer.Y < snowTop - 8) continue;
                float mass = shelf.Snow.Sweep(x, velocity);
                if (mass <= 0) continue;
                AddGrain(new SnowGrain
                {
                    Position = new Vector2(pointer.X, snowTop - 1),
                    Velocity = new Vector2(Math.Clamp(velocity * .20f, -160, 160), Range(-85, -38)),
                    Radius = Range(1.1f, 2.6f),
                    Mass = mass,
                    Life = 4
                });
                break;
            }
        }
    }

    private void StepPlow(float delta, PlowPass pass, bool reducedMotion)
    {
        pass.Step(delta);
        float lead = pass.Direction * 9;
        float removed = floor.Snow.RemoveInSpan(Math.Min(pass.Previous, pass.Blade) + lead - 2,
            Math.Max(pass.Previous, pass.Blade) + lead + 2, .30f);
        powderLoad = Math.Min(18, powderLoad * MathF.Exp(-3.8f * delta) + removed * .42f);
        if (removed <= .05f || reducedMotion) return;

        int count = Math.Clamp((int)(removed * .7f), 1, 5);
        for (int i = 0; i < count; i++)
        {
            AddGrain(new SnowGrain
            {
                Position = new Vector2(pass.Blade + pass.Direction * Range(9, 26), FloorY - Range(6, 17)),
                Velocity = new Vector2(pass.Direction * Range(28, 134), Range(-122, -38)),
                Radius = Range(1.2f, 4.0f),
                Mass = removed * .23f / count,
                Life = 3
            });
        }
    }

    private void AddGrain(SnowGrain grain)
    {
        if (grains.Count >= 520) grains.RemoveAt(0);
        grains.Add(grain);
    }

    private float Unit() => random.NextSingle();
    private float Range(float low, float high) => low + Unit() * (high - low);
}
