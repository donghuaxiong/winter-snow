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
    public float Angle;
    public SnowCornerSlide? Slide;

    public float ClumpWidth => Math.Min(13, 6 + Mass * .75f);
    public Vector2 Contact
    {
        get
        {
            if (Slide is null) return Position + new Vector2(0, Radius * .6f);
            float along = ClumpWidth / 2 * MathF.Sin(Angle);
            float across = Radius * MathF.Cos(Angle);
            return Position + new Vector2(0, MathF.Sqrt(along * along + across * across));
        }
    }
}

internal sealed class SnowCornerSlide(Shelf source, bool left, bool reducedMotion)
{
    public readonly Shelf Source = source;
    public readonly float Direction = left ? -1 : 1;
    private readonly float duration = reducedMotion ? .16f : .31f;
    private float elapsed;

    public bool Rolling => elapsed < duration;
    public bool Exposed => left ? Source.LeftOverflow : Source.RightOverflow;
    private float Edge => left ? Source.Frame.Left : Source.Frame.Right;

    public Vector2 Position(float depth, out float turn)
    {
        float progress = elapsed / duration;
        turn = (.64f * progress + .36f * progress * progress) * MathF.PI / 2;
        float radius = Source.Radius;
        float shell = radius + depth * .48f;
        return new Vector2(Edge + Direction * (shell * MathF.Sin(turn) - radius), Source.Frame.Top + radius - shell * MathF.Cos(turn));
    }

    public void Advance(float delta) => elapsed = Math.Min(duration, elapsed + delta);
    public void Release() => elapsed = duration;
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
    private bool hasEmittedSnow;
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
                shelf.LeftOverflow = CanOverflow(shelf, true);
                shelf.RightOverflow = CanOverflow(shelf, false);
                shelf.Snow.Resize(frame.Width);
                if (shelf.Visible.Count > 0) shelves.Add(shelf);

                bool CanOverflow(Shelf owner, bool left) => owner.OverflowRoute(left, viewport, floorY) is { } route &&
                    !nearer.Exists(cover => cover.Intersect(route).HasArea);
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

    public void StopAirborneFlakes() => flakes.Clear();

    public void Step(float delta, SnowOptions options, bool snowing, bool reducedMotion, Vector2? previousMouse, Vector2? mouse)
    {
        ShowIcicles = options.Icicles && options.Accumulation;
        if (snowing || flakes.Count > 0)
        {
            weatherTime += delta;
            FlyFlakes(delta, options, reducedMotion, emitting: snowing);
        }
        if (snowing && options.Accumulation)
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

        if (options.Accumulation && (snowing || flakes.Count > 0 || grains.Count > 0 || Plow is not null))
        {
            settleClock += delta;
            if (settleClock > .18f)
            {
                settleClock = 0;
                foreach (Shelf shelf in shelves) shelf.Snow.Settle();
                if (snowing) SpillWindowCorners(reducedMotion);
            }

            if (cooldown > 0) cooldown -= delta;
            if (snowing && options.AutomaticPlow && cooldown <= 0 && Plow is null && floor.Snow.DeepEnough)
                StartPlow();
        }

        Person?.Step(delta, Monitor.Width, FloorY, reducedMotion);
        StepGrains(delta, options.Accumulation, reducedMotion);
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

    private void FlyFlakes(float delta, SnowOptions options, bool reducedMotion, bool emitting)
    {
        if (emitting)
        {
            int target = (int)Math.Clamp(Monitor.Width * Monitor.Height / 4400 * options.Density * 1.70f, 0, 730);
            if (reducedMotion) target /= 3;
            if (flakes.Count > target) flakes.RemoveRange(target, flakes.Count - target);
            int missing = target - flakes.Count;
            int count = hasEmittedSnow ? Math.Min(missing, 32) : missing;
            for (int i = 0; i < count; i++) flakes.Add(NewFlake(scattered: !hasEmittedSnow));
            hasEmittedSnow |= count > 0;
        }

        int remaining = 0;
        for (int i = 0; i < flakes.Count; i++)
        {
            Flake flake = flakes[i];
            if (!emitting && flake.Position.Y + flake.Radius < 0) continue;
            Vector2 old = flake.Position;
            float sway = reducedMotion ? 0 : 14 * MathF.Sin(weatherTime * .84f + flake.Phase);
            flake.Position += new Vector2((options.Wind * 56 + sway) * delta, flake.Speed * (.30f + options.Speed * 1.25f) * delta);
            if (flake.Position.X < -8) flake.Position.X += Monitor.Width + 16;
            if (flake.Position.X > Monitor.Width + 8) flake.Position.X -= Monitor.Width + 16;
            Shelf? shelf = null;
            if (options.Accumulation) FindLanding(old.Y, flake.Position, out shelf);
            if (shelf is not null) shelf.Snow.Land(flake.Position.X - shelf.Frame.Left, .36f + .65f * flake.Radius);
            if (shelf is not null || flake.Position.Y > FloorY + 8)
            {
                if (!emitting) continue;
                flake = NewFlake(scattered: false);
            }
            flakes[remaining++] = flake;
        }
        if (remaining < flakes.Count) flakes.RemoveRange(remaining, flakes.Count - remaining);
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

    private bool FindLanding(float oldY, Vector2 point, out Shelf? support, Shelf? source = null)
    {
        float lowestY = float.MaxValue;
        support = null;
        foreach (Shelf shelf in shelves)
        {
            if (shelf == source || shelf.Frame.Top - 25 > point.Y || !shelf.Supports(point.X)) continue;
            float snowTop = shelf.TopAt(point.X) - shelf.Snow.At(point.X - shelf.Frame.Left);
            if (oldY > snowTop + 2 || point.Y < snowTop || snowTop >= lowestY) continue;
            lowestY = snowTop;
            support = shelf;
        }
        return support is not null;
    }

    private void SpillWindowCorners(bool reducedMotion)
    {
        foreach (Shelf shelf in shelves)
        {
            if (grains.Count >= 500) return;
            if (shelf.IsFloor) continue;
            for (int side = 0; side < 2; side++)
            {
                bool left = side == 0;
                if (!(left ? shelf.LeftOverflow : shelf.RightOverflow)) continue;
                if (SettingsCover is { } cover && shelf.OverflowRoute(left, viewport, FloorY) is { } route && cover.Intersect(route).HasArea)
                    continue;
                float mass = shelf.Snow.SpillFromCorner(left, weatherTime);
                if (mass <= 0) continue;
                var slide = new SnowCornerSlide(shelf, left, reducedMotion);
                float width = Math.Min(13, 6 + mass * .75f);
                float thickness = Math.Clamp(mass * 6 / width * .86f, 2.5f, 5.2f);
                AddGrain(new SnowGrain
                {
                    Position = slide.Position(thickness, out _),
                    Velocity = new Vector2(slide.Direction * Range(14, 27), 65),
                    Radius = thickness / 2, Mass = mass, Life = 7, Slide = slide
                });
                break;
            }
        }
    }

    private void StepGrains(float delta, bool collect, bool reducedMotion)
    {
        for (int i = grains.Count - 1; i >= 0; i--)
        {
            SnowGrain grain = grains[i];
            var slide = grain.Slide;
            float oldY = grain.Contact.Y;
            bool rolling = slide is { Rolling: true, Exposed: true } && shelves.Contains(slide.Source);
            if (rolling)
            {
                slide!.Advance(delta);
                grain.Position = slide.Position(grain.Radius * 2, out float turn);
                if (!reducedMotion) grain.Angle = slide.Direction * turn;
                if (!slide.Rolling) oldY = Math.Min(oldY, slide.Source.Frame.Top);
            }
            else
            {
                slide?.Release();
                grain.Velocity.Y += 570 * delta;
                grain.Position += grain.Velocity * delta;
                if (slide is not null)
                {
                    if (!reducedMotion) grain.Angle += slide.Direction * 1.8f * delta;
                    grain.Position.X = Math.Clamp(grain.Position.X, 1, Math.Max(1, viewport.Width - 1));
                }
            }
            grain.Life -= delta;
            Vector2 contact = grain.Contact;
            if (collect && slide?.Rolling != true && grain.Velocity.Y >= 0 && grain.Mass > 0 &&
                FindLanding(oldY, contact, out Shelf? landing, slide?.Source))
            {
                float x = contact.X - landing!.Frame.Left;
                if (slide is null) landing.Snow.Land(x, grain.Mass);
                else landing.Snow.DepositClump(x, grain.Mass);
                grains.RemoveAt(i);
            }
            else if (collect && slide is { Rolling: false } && contact.Y >= FloorY - floor.Snow.At(contact.X))
            {
                floor.Snow.DepositClump(contact.X, grain.Mass);
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
