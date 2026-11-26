using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Snowglow.Windows;

internal sealed class DesktopController : IDisposable
{
    private sealed class Display
    {
        public readonly SnowScene Scene;
        public readonly WeatherVisual Visual;
        public readonly Overlay Layer;

        public Display(MonitorInfo monitor)
        {
            Scene = new SnowScene(monitor);
            Visual = new WeatherVisual(Scene);
            Layer = new Overlay(Visual, passthrough: true);
            Layer.Place(monitor.Pixels);
        }
    }

    private sealed class Drag(Snowperson person, Vector2 start, Vector2 offset, int part)
    {
        public readonly Snowperson Person = person;
        public readonly Vector2 Start = start;
        public readonly Vector2 Offset = offset;
        public readonly int Part = part;
        public bool Moved;
    }

    private sealed record PlacementRequest(Guid? Id, bool Window, Action<string> Complete)
    {
        internal bool Ready;
    }

    private sealed record DecorationDrag(Guid Id, Vector2 Start, Vector2 Offset)
    {
        internal bool Moved;
    }

    private sealed record DecorationHandle(DecorationGrip Grip, Overlay Layer);

    public Settings Options { get; private set; }
    public event Action? Changed;
    public Window? SettingsWindow { get; set; }

    private readonly Dictionary<string, Display> displays = new(StringComparer.Ordinal);
    private readonly DispatcherTimer frameTimer;
    private readonly DispatcherTimer saveTimer;
    private readonly SnowmanGrip grip = new();
    private readonly Overlay gripWindow;
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly bool live;
    private Drag? drag;
    private double lastFrame, lastScan = -1, lastMonitorScan = -2;
    private Vector2 lastCursor;
    private bool haveCursor;
    private PlacementRequest? placementRequest;
    private List<WindowSample> desktopWindows = [];
    private Action? endPreview;
    private uint? previewStamp;
    private bool preview;
    private bool idle;
    private Action? endDecorationEditing;
    private DecorationDrag? decorationDrag;
    private readonly Dictionary<Guid, DecorationHandle> decorationHandles = [];

    public DesktopController(Settings options, bool live = true)
    {
        Options = options;
        this.live = live;
        gripWindow = new Overlay(grip, passthrough: false);
        grip.Grabbed += BeginDrag;
        grip.Moved += UpdateDrag;
        grip.Dropped += FinishDrag;
        grip.Knocked += Knock;

        saveTimer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(400) };
        saveTimer.Tick += (_, _) => { saveTimer.Stop(); Options.Save(); };
        frameTimer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(32) };
        frameTimer.Tick += Frame;
        if (live)
        {
            Frame(null, EventArgs.Empty);
            frameTimer.Start();
        }
    }

    public void Apply()
    {
        foreach (Display display in displays.Values)
        {
            display.Scene.Person?.ApplyClothes(Options, display.Scene.FloorY);
            display.Visual.InvalidateVisual();
        }
        saveTimer.Stop();
        saveTimer.Start();
        Changed?.Invoke();
    }

    public void ToggleAccumulation()
    {
        Options.Accumulation = !Options.Accumulation;
        if (!Options.Accumulation) ClearSnow();
        Apply();
    }

    public void AddOrResetSnowman()
    {
        FinishDrag();
        var cursor = NativeDesktop.Cursor();
        if ((At(cursor) ?? Primary()) is not { } display) return;
        foreach (Display view in displays.Values) view.Scene.Person = null;
        float x = Math.Clamp(display.Scene.Monitor.ToLocal(cursor).X, 47, Math.Max(47, display.Scene.Monitor.Width - 47));
        display.Scene.Person = new Snowperson(new Vector2(x, display.Scene.FloorY - 1), false, Options.Outfit);
        Options.ShowSnowman = true;
        SavePose(display);
        UpdateGrip();
    }

    public void RemoveSnowman()
    {
        FinishDrag();
        foreach (Display display in displays.Values) display.Scene.Person = null;
        Options.ShowSnowman = false;
        Options.Placement = null;
        Apply();
        UpdateGrip();
    }

    public bool PlowNow() => (At(NativeDesktop.Cursor()) ?? Primary())?.Scene.StartPlow() == true;

    public void ClearSnow()
    {
        foreach (Display display in displays.Values) display.Scene.ClearSnow();
    }

    public void Preview(Action? complete = null)
    {
        if (preview) return;
        preview = true;
        previewStamp = NativeDesktop.LastInputStamp;
        endPreview = complete;
    }

    public string ApplyWallpaper(Wallpaper wallpaper) =>
        UpdateWallpaper(() => DesktopWallpaperService.Apply(Options, wallpaper));

    public string RestoreWallpaper() =>
        UpdateWallpaper(() => DesktopWallpaperService.Restore(Options));

    private string UpdateWallpaper(Func<string> action)
    {
        try { return action(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or COMException)
        {
            Trace.TraceWarning(error.Message);
            return "Windows 未完成更换壁纸。请检查系统个性化设置后重试。";
        }
        finally { Apply(); }
    }

    public string ApplyCabin()
    {
        Options.Snow = Options.Accumulation = Options.AutomaticPlow = true;
        Options.OnlyIdle = false;
        Options.Density = .58f;
        Options.Wind = -.10f;
        Options.Speed = .52f;
        return ApplyWallpaper(Wallpaper.Find(Wallpaper.Cabin)!);
    }

    public void SaveScene(string caption)
    {
        string name = caption.Trim();
        if (name.Length == 0) return;
        int previous = Options.Scenes.FindIndex(scene => string.Equals(scene.Name, name, StringComparison.OrdinalIgnoreCase));
        var scene = new SavedScene(previous >= 0 ? Options.Scenes[previous].Id : Guid.NewGuid(), name, Options.Snapshot());
        if (previous >= 0) Options.Scenes[previous] = scene;
        else Options.Scenes.Add(scene);
        Apply();
    }

    public string LoadScene(SavedScene scene)
    {
        FinishDrag();
        string? wallpaper = Options.Wallpaper;
        Options = Options.WithScene(scene.Options);
        Options.Wallpaper = wallpaper;
        foreach (Display display in displays.Values) display.Scene.Person = null;
        RestoreSnowman();
        if (!Options.Accumulation) ClearSnow();
        Apply();
        if (scene.Options.Wallpaper == wallpaper) return $"已载入「{scene.Name}」";
        string result = Wallpaper.Find(scene.Options.Wallpaper) is { } art ? ApplyWallpaper(art) : RestoreWallpaper();
        return $"已载入「{scene.Name}」。{result}";
    }

    public Decoration AddDecoration(DecorationKind kind)
    {
        if (kind == DecorationKind.Calendar && Options.Decorations.FirstOrDefault(d => d.Kind == kind) is { } existing)
            return existing;
        var monitor = (At(NativeDesktop.Cursor()) ?? Primary())?.Scene.Monitor.Name ?? string.Empty;
        float shift = Options.Decorations.Count % 5 * .07f;
        var item = new Decoration(Guid.NewGuid(), kind, monitor, .74f - shift, .35f + shift);
        Options.Decorations.Add(item);
        Options.ShowDecorations = true;
        Apply();
        return item;
    }

    public void ChangeDecoration(Guid id, Func<Decoration, Decoration> update)
    {
        int index = Options.Decorations.FindIndex(item => item.Id == id);
        if (index < 0) return;
        Options.Decorations[index] = update(Options.Decorations[index]);
        Apply();
    }

    public void RemoveDecoration(Guid id)
    {
        Options.Decorations.RemoveAll(item => item.Id == id);
        Apply();
    }

    public void PlaceDecoration(Guid id, bool attach, Action<string> complete) =>
        placementRequest = new PlacementRequest(id, attach, complete);

    public void PlaceSnowmanOnWindow(Action<string> complete) =>
        placementRequest = new PlacementRequest(null, true, complete);

    public void CancelPlacement()
    {
        if (placementRequest is not { } request) return;
        placementRequest = null;
        request.Complete("已取消摆放。");
    }

    public void EditDecorations(Action complete) => endDecorationEditing = complete;

    public void StopEditingDecorations()
    {
        if (endDecorationEditing is not { } completed) return;
        endDecorationEditing = null;
        FinishDecorationDrag();
        foreach (DecorationHandle handle in decorationHandles.Values) handle.Layer.Destroy();
        decorationHandles.Clear();
        completed();
    }

    private void Frame(object? sender, EventArgs e)
    {
        double now = clock.Elapsed.TotalSeconds;
        float delta = Math.Clamp((float)(now - lastFrame), .001f, .064f);
        lastFrame = now;
        if (now - lastMonitorScan >= 1)
        {
            lastMonitorScan = now;
            RefreshDisplays();
        }

        Vector2 cursor = NativeDesktop.Cursor();
        bool pressed = NativeDesktop.PrimaryMouseDown;
        uint? input = preview || Options.IdleSeconds > 0 ? NativeDesktop.LastInputStamp : null;
        if (preview && input is { } stamp && previewStamp is { } initial && stamp != initial)
        {
            preview = false;
            Action? completed = endPreview;
            endPreview = null;
            completed?.Invoke();
        }
        idle = Options.IdleSeconds > 0 && input is { } last && NativeDesktop.IdleMilliseconds(last) >= Options.IdleSeconds * 1000u;
        bool snowing = preview || Options.Snow && (!Options.OnlyIdle || idle);
        UpdatePlacement(cursor, pressed);
        if (endDecorationEditing is not null && NativeDesktop.EscapeDown) StopEditingDecorations();
        if (decorationDrag is not null)
        {
            UpdateDecorationDrag(cursor);
            if (!pressed) FinishDecorationDrag();
        }
        if (drag is not null)
        {
            UpdateDrag(cursor);
            if (!pressed)
            {
                FinishDrag();
                grip.EndGesture();
            }
        }
        if (now - lastScan >= (pressed ? .030 : .078))
        {
            desktopWindows = NativeDesktop.Windows(endDecorationEditing is not null || Options.Placement?.Window is not null ||
                Options.Decorations.Any(d => d.Window is not null));
            foreach (Display display in displays.Values)
                display.Scene.SetDesktop(desktopWindows, now, (float)(now - lastScan), Options.Accumulation);
            PositionAnchoredSnowman();
            lastScan = now;
        }

        Box? cover = null;
        if (SettingsWindow is { IsVisible: true, WindowState: not WindowState.Minimized } settings &&
            NativeDesktop.TryWindowBounds(new WindowInteropHelper(settings).Handle, out Box bounds) && bounds.HasArea)
            cover = bounds;

        bool hadSnowman = Options.ShowSnowman;
        bool reducedMotion = !SystemParameters.ClientAreaAnimation;
        foreach (Display display in displays.Values)
        {
            SnowScene scene = display.Scene;
            var monitor = scene.Monitor;
            if (!snowing && Options.Snow) scene.StopAirborneFlakes();
            scene.SettingsCover = cover is { } rect ? monitor.ToLocal(rect) : null;
            UpdateDecorations(scene);
            bool sweeping = haveCursor && !pressed && monitor.Pixels.Contains(cursor) && monitor.Pixels.Contains(lastCursor);
            var movingPlow = scene.Plow;
            scene.Step(delta, Options, snowing, reducedMotion, sweeping ? monitor.ToLocal(lastCursor) : null,
                sweeping ? monitor.ToLocal(cursor) : null);
            UpdateFlakeCovers(scene);
            if (Options.PlowCollision && movingPlow is not null) CheckDecorationCollisions(scene, movingPlow);
            display.Visual.Dim = snowing && Options.IdleDim && (preview || idle);
            display.Visual.Time = reducedMotion ? 0 : now;
            display.Visual.InvalidateVisual();
        }
        if (hadSnowman != Options.ShowSnowman) Apply();
        if (endDecorationEditing is not null) UpdateDecorationHandles();
        lastCursor = cursor;
        haveCursor = true;
        UpdateGrip();
    }

    private void UpdateDecorationHandles()
    {
        var seen = new HashSet<Guid>();
        foreach (Display display in displays.Values)
        {
            var monitor = display.Scene.Monitor;
            var viewport = new Box(0, 0, monitor.Width, monitor.Height);
            foreach (PlacedDecoration decoration in display.Scene.Decorations)
            {
                Box box = decoration.Bounds.Intersect(viewport);
                if (!box.HasArea || !seen.Add(decoration.Item.Id)) continue;
                Guid key = decoration.Item.Id;
                if (!decorationHandles.TryGetValue(key, out DecorationHandle? handle))
                {
                    var hit = new DecorationGrip();
                    hit.Grabbed += pointer => BeginDecorationDrag(key, pointer);
                    hit.Dropped += FinishDecorationDrag;
                    handle = new DecorationHandle(hit, new Overlay(hit, passthrough: false));
                    decorationHandles.Add(key, handle);
                }
                Vector2 min = monitor.ToPixel(new Vector2(box.Left, box.Top)), max = monitor.ToPixel(new Vector2(box.Right, box.Bottom));
                handle.Layer.Place(new Box(min.X, min.Y, max.X, max.Y));
            }
        }
        foreach (Guid key in decorationHandles.Keys.Where(key => !seen.Contains(key) && decorationDrag?.Id != key).ToArray())
        {
            decorationHandles[key].Layer.Destroy();
            decorationHandles.Remove(key);
        }
    }

    private void BeginDecorationDrag(Guid key, Vector2 pointer)
    {
        if (At(pointer) is not { } display) return;
        Vector2 local = display.Scene.Monitor.ToLocal(pointer);
        var item = display.Scene.Decorations.FirstOrDefault(entry => entry.Item.Id == key);
        if (!item.Bounds.HasArea) return;
        decorationDrag = new DecorationDrag(key, pointer, new Vector2(item.Bounds.MidX, item.Bounds.Bottom) - local);
    }

    private void UpdateDecorationDrag(Vector2 cursor)
    {
        if (decorationDrag is not { } move || At(cursor) is not { } display) return;
        if (!move.Moved && Vector2.DistanceSquared(move.Start, cursor) < 18) return;
        move.Moved = true;
        int index = Options.Decorations.FindIndex(item => item.Id == move.Id);
        if (index < 0) return;
        var scene = display.Scene;
        Vector2 position = scene.Monitor.ToLocal(cursor) + move.Offset;
        Options.Decorations[index] = Options.Decorations[index] with
        {
            Window = null,
            Monitor = scene.Monitor.Name,
            X = Math.Clamp(position.X / scene.Monitor.Width, 0, 1),
            Y = Math.Clamp(position.Y / scene.FloorY, 0, 1)
        };
    }

    private void FinishDecorationDrag()
    {
        if (decorationDrag is not { } move) return;
        decorationDrag = null;
        Vector2 cursor = NativeDesktop.Cursor();
        if (move.Moved && At(cursor) is { } display)
        {
            var window = desktopWindows.FirstOrDefault(candidate => candidate.Key is not null &&
                cursor.X >= candidate.Frame.Left && cursor.X <= candidate.Frame.Right &&
                Math.Abs(cursor.Y - candidate.Frame.Top) <= 24 * display.Scene.Monitor.Scale);
            if (window.Key is not null)
                ChangeDecoration(move.Id, item => item with { Window = window.Key,
                    X = Math.Clamp((cursor.X - window.Frame.Left) / window.Frame.Width, .05f, .95f) });
            else Apply();
        }
        else if (!move.Moved && At(cursor) is { } owner)
        {
            var placed = owner.Scene.Decorations.FirstOrDefault(entry => entry.Item.Id == move.Id);
            if (!placed.Bounds.HasArea || placed.Item.Kind != DecorationKind.Calendar) return;
            Vector2 point = owner.Scene.Monitor.ToLocal(cursor);
            float x = (point.X - placed.Bounds.Left) / placed.Bounds.Width * 272;
            float y = (point.Y - placed.Bounds.Top) / placed.Bounds.Height * 225;
            int col = (int)Math.Floor((x - 17) / 48), row = (int)Math.Floor((y - 51) / 31);
            int day = row * 5 + col + 1;
            if (col is >= 0 and < 5 && row is >= 0 and < 5 && day <= DecorationArt.AvailableDoors(DateTime.Now))
                ChangeDecoration(move.Id, item => item with { Opened = item.Opened | (1 << (day - 1)) });
        }
    }

    private void UpdateFlakeCovers(SnowScene scene)
    {
        scene.FlakeCovers.Clear();
        if (scene.Flakes.Count == 0 || preview || Options.Layer == SnowLayer.InFront) return;
        nint foreground = Options.Layer == SnowLayer.BehindFrontWindow ? NativeDesktop.ForegroundWindow : 0;
        var viewport = new Box(0, 0, scene.Monitor.Width, scene.Monitor.Height);
        foreach (WindowSample window in desktopWindows)
        {
            if (window.Taskbar || Options.Layer == SnowLayer.BehindFrontWindow && window.Handle != foreground) continue;
            var rect = scene.Monitor.ToLocal(window.Frame).Intersect(viewport);
            if (rect.HasArea) scene.FlakeCovers.Add(rect);
        }
    }

    private void UpdateDecorations(SnowScene scene)
    {
        scene.Decorations.Clear();
        if (!Options.ShowDecorations) return;
        var monitor = scene.Monitor;
        var viewport = new Box(0, 0, monitor.Width, monitor.Height);
        foreach (Decoration item in Options.Decorations)
        {
            var (width, height) = DecorationArt.Size(item.Kind);
            width *= item.Scale;
            height *= item.Scale;
            Box box;
            if (item.Window is { } key)
            {
                var window = desktopWindows.FirstOrDefault(sample => sample.Key == key && !sample.Taskbar);
                if (window.Handle == 0) continue;
                var frame = monitor.ToLocal(window.Frame);
                float center = frame.Left + frame.Width * item.X;
                box = item.Kind == DecorationKind.Lights
                    ? new Box(frame.Left + 5, frame.Top, frame.Right - 5, frame.Top + height)
                    : new Box(center - width / 2, frame.Top - height + 4, center + width / 2, frame.Top + 4);
            }
            else
            {
                string? target = displays.ContainsKey(item.Monitor) ? item.Monitor : Primary()?.Scene.Monitor.Name;
                if (monitor.Name != target) continue;
                float x = Math.Clamp(monitor.Width * item.X, width / 2, Math.Max(width / 2, monitor.Width - width / 2));
                float bottom = Math.Clamp(scene.FloorY * item.Y, Math.Min(height, scene.FloorY), scene.FloorY);
                box = new Box(x - width / 2, bottom - height, x + width / 2, bottom);
            }
            if (box.Intersect(viewport).HasArea) scene.Decorations.Add(new PlacedDecoration(item, box));
        }
    }

    private void CheckDecorationCollisions(SnowScene scene, PlowPass plow)
    {
        float left = Math.Min(plow.Previous, plow.Blade), right = Math.Max(plow.Previous, plow.Blade);
        bool changed = false;
        for (int index = scene.Decorations.Count - 1; index >= 0; index--)
        {
            var placed = scene.Decorations[index];
            if (placed.Item.Window is not null || placed.Bounds.Bottom < scene.FloorY - 26 ||
                placed.Bounds.Right < left || placed.Bounds.Left > right) continue;
            Options.Decorations.RemoveAll(item => item.Id == placed.Item.Id);
            scene.Decorations.RemoveAt(index);
            changed = true;
        }
        if (changed) Apply();
    }

    private void UpdatePlacement(Vector2 cursor, bool pressed)
    {
        if (placementRequest is not { } request) return;
        if (NativeDesktop.EscapeDown) { CancelPlacement(); return; }
        if (!pressed) { request.Ready = true; return; }
        if (!request.Ready || At(cursor) is not { } display) return;
        placementRequest = null;
        var scene = display.Scene;
        var position = scene.Monitor.ToLocal(cursor);
        if (request.Window)
        {
            var window = NativeDesktop.Windows(includeIdentity: true).FirstOrDefault(
                candidate => candidate.Key is not null && !candidate.Taskbar && candidate.Frame.Contains(cursor));
            if (window.Key is null) { request.Complete("没有找到可挂靠的窗口。"); return; }
            float anchor = Math.Clamp((cursor.X - window.Frame.Left) / window.Frame.Width, .1f, .9f);
            if (request.Id is { } id)
                ChangeDecoration(id, item => item with { Window = window.Key, X = anchor, Monitor = scene.Monitor.Name });
            else
            {
                AddOrResetSnowman();
                if (Owner() is { } owner && owner.Scene.Person is { } person)
                {
                    person.Anchor = window.Key;
                    person.AnchorX = anchor;
                    person.Manual = true;
                    SavePose(owner);
                }
            }
            lastScan = -1;
            request.Complete(request.Id is null ? "雪人已放到窗口上。" : "装饰已挂到窗口。");
        }
        else if (request.Id is { } id)
        {
            ChangeDecoration(id, item => item with { Window = null, Monitor = scene.Monitor.Name,
                X = Math.Clamp(position.X / scene.Monitor.Width, 0, 1), Y = Math.Clamp(position.Y / scene.FloorY, 0, 1) });
            request.Complete("装饰已放到桌面。");
        }
    }

    private void PositionAnchoredSnowman()
    {
        if (Owner() is not { } owner || owner.Scene.Person is not { Anchor: { } key, Dragging: false } person) return;
        var window = desktopWindows.FirstOrDefault(item => item.Key == key);
        if (window.Handle == 0)
        {
            person.FallFromWindow();
            SavePose(owner);
            return;
        }
        var feet = new Vector2(window.Frame.Left + window.Frame.Width * person.AnchorX, window.Frame.Top + 2);
        Display target = At(feet) ?? owner;
        if (target != owner)
        {
            owner.Scene.Person = null;
            target.Scene.Person = person;
        }
        person.Feet = target.Scene.Monitor.ToLocal(feet);
        person.Pose(target.Scene.FloorY);
    }

    private void RefreshDisplays()
    {
        var live = NativeDesktop.Monitors();
        bool changed = live.Count != displays.Count || live.Any(monitor =>
            !displays.TryGetValue(monitor.Name, out Display? current) || current.Scene.Monitor != monitor);
        if (!changed) return;
        if (drag is not null)
        {
            FinishDrag();
            grip.EndGesture();
        }
        foreach (string device in displays.Keys.ToArray())
        {
            if (live.Any(monitor => monitor.Name == device && monitor == displays[device].Scene.Monitor)) continue;
            displays[device].Layer.Destroy();
            displays.Remove(device);
        }
        foreach (MonitorInfo monitor in live)
            if (!displays.ContainsKey(monitor.Name))
                displays.Add(monitor.Name, new Display(monitor));

        RestoreSnowman();
        lastScan = -1;
    }

    private void RestoreSnowman()
    {
        if (Owner() is null && Options.ShowSnowman)
        {
            SnowmanPlacement? saved = Options.Placement;
            Display? target = saved is not null && displays.TryGetValue(saved.Monitor, out Display? savedDisplay) ? savedDisplay : Primary();
            if (target is not null)
            {
                SnowScene scene = target.Scene;
                bool manual = saved?.Y is not null;
                var feet = ClampFeet(scene, new Vector2((saved?.X ?? .78f) * scene.Monitor.Width,
                    (saved?.Y ?? 1) * scene.Monitor.Height), manual);
                scene.Person = new Snowperson(feet, manual, Options.Outfit);
                scene.Person.Anchor = saved?.Window;
                scene.Person.AnchorX = saved?.X ?? .5f;
                if (scene.Person.Anchor is not null) scene.Person.Manual = true;
                scene.Person.ApplyClothes(Options, scene.FloorY);
                scene.Person.Pose(scene.FloorY);
            }
        }
    }

    private void BeginDrag(Vector2 pointer)
    {
        var owner = Owner();
        if (owner?.Scene.Person is not { } person) return;
        Vector2 position = owner.Scene.Monitor.ToLocal(pointer);
        int part = person.Tumbled ? ClosestBall(person, position) : -1;
        Vector2 center = part < 0 ? person.Feet : person.Balls[part].Center;
        person.Dragging = true;
        if (part >= 0) person.Held = part;
        drag = new Drag(person, pointer, center - position, part);
    }

    private void UpdateDrag(Vector2 pointer)
    {
        var motion = drag;
        var owner = Owner();
        if (motion is null || owner is null) return;
        if (!motion.Moved && Vector2.DistanceSquared(pointer, motion.Start) < 12) return;
        motion.Moved = true;
        var person = motion.Person;
        var display = motion.Part < 0 ? At(pointer) ?? owner : owner;
        var scene = display.Scene;
        Vector2 position = scene.Monitor.ToLocal(pointer) + motion.Offset;
        if (motion.Part < 0)
        {
            person.Anchor = null;
            if (display != owner)
            {
                owner.Scene.Person = null;
                scene.Person = person;
                owner.Visual.InvalidateVisual();
            }
            person.Feet = ClampFeet(scene, position, manual: true);
            person.Manual = true;
            person.Pose(scene.FloorY);
        }
        else
        {
            var ball = person.Balls[motion.Part];
            ball.Center = new Vector2(Math.Clamp(position.X, ball.Radius, Math.Max(ball.Radius, scene.Monitor.Width - ball.Radius)),
                Math.Clamp(position.Y, ball.Radius, Math.Max(ball.Radius, scene.FloorY - ball.Radius)));
            ball.Velocity = Vector2.Zero;
        }
        display.Visual.InvalidateVisual();
        UpdateGrip();
    }

    private void FinishDrag()
    {
        if (drag is not { } motion) return;
        drag = null;
        motion.Person.Dragging = false;
        motion.Person.Held = -1;
        if (motion.Moved && motion.Part < 0 && Owner() is { } display) SavePose(display);
        if (!motion.Moved && motion.Part >= 0 && Owner() is { } source)
            Rebuild(source, motion.Person.Balls[motion.Part].Center.X);
    }

    private void Knock(Vector2 pointer)
    {
        var owner = Owner();
        if (owner?.Scene.Person is not { } person) return;
        SnowScene scene = owner.Scene;
        float x = scene.Monitor.ToLocal(pointer).X;
        if (person.Tumbled) Rebuild(owner, x);
        else
        {
            person.ToggleTumble(x, scene.Monitor.Width, scene.FloorY, !SystemParameters.ClientAreaAnimation);
            owner.Visual.InvalidateVisual();
            UpdateGrip();
        }
    }

    private void Rebuild(Display display, float x)
    {
        SnowScene scene = display.Scene;
        scene.Person?.ToggleTumble(x, scene.Monitor.Width, scene.FloorY, !SystemParameters.ClientAreaAnimation);
        SavePose(display);
        display.Visual.InvalidateVisual();
        UpdateGrip();
    }

    private void SavePose(Display display)
    {
        if (display.Scene.Person is { } person)
        {
            MonitorInfo monitor = display.Scene.Monitor;
            Options.Placement = new SnowmanPlacement(monitor.Name,
                person.Anchor is null ? person.Feet.X / monitor.Width : person.AnchorX,
                person.Manual ? person.Feet.Y / monitor.Height : null, person.Anchor);
        }
        Apply();
    }

    private void UpdateGrip()
    {
        if (Owner() is not { } display || display.Scene.Person is not { } person)
        {
            if (gripWindow.IsVisible) gripWindow.Hide();
            return;
        }

        var monitor = display.Scene.Monitor;
        float left = float.MaxValue, top = float.MaxValue, right = float.MinValue, bottom = float.MinValue;
        foreach (Snowball ball in person.Balls)
        {
            float r = ball.Radius + 4;
            left = Math.Min(left, ball.Center.X - r);
            top = Math.Min(top, ball.Center.Y - r);
            right = Math.Max(right, ball.Center.X + r);
            bottom = Math.Max(bottom, ball.Center.Y + r);
        }

        var hit = new Box(left, top, right, bottom);
        if (!person.Dragging && display.Scene.SettingsCover is { } cover && cover.Intersect(hit).HasArea)
        {
            if (gripWindow.IsVisible) gripWindow.Hide();
            return;
        }
        Vector2 min = monitor.ToPixel(new Vector2(hit.Left, hit.Top));
        Vector2 max = monitor.ToPixel(new Vector2(hit.Right, hit.Bottom));
        var frame = new Box(MathF.Floor(min.X), MathF.Floor(min.Y), MathF.Ceiling(max.X), MathF.Ceiling(max.Y));
        grip.Update(person, monitor, frame);
        gripWindow.Place(frame);
    }

    private static int ClosestBall(Snowperson person, Vector2 target)
    {
        int closest = 0;
        float best = float.MaxValue;
        for (int index = 0; index < person.Balls.Count; index++)
        {
            Snowball ball = person.Balls[index];
            float distance = Vector2.DistanceSquared(ball.Center, target) / (ball.Radius * ball.Radius);
            if (distance >= best) continue;
            closest = index;
            best = distance;
        }
        return closest;
    }

    private static Vector2 ClampFeet(SnowScene scene, Vector2 point, bool manual) =>
        new(Math.Clamp(point.X, 47, Math.Max(47, scene.Monitor.Width - 47)),
            manual ? Math.Clamp(point.Y, Math.Min(142, scene.FloorY), scene.FloorY) : scene.FloorY - 1);

    private Display? At(Vector2 cursor) => displays.Values.FirstOrDefault(display => display.Scene.Monitor.Pixels.Contains(cursor));
    private Display? Primary() => displays.Values.FirstOrDefault(display => display.Scene.Monitor.Primary) ?? displays.Values.FirstOrDefault();
    private Display? Owner() => displays.Values.FirstOrDefault(display => display.Scene.Person is not null);

    public void Dispose()
    {
        frameTimer.Stop();
        saveTimer.Stop();
        FinishDrag();
        saveTimer.Stop();
        if (live) Options.Save();
        foreach (DecorationHandle handle in decorationHandles.Values) handle.Layer.Destroy();
        decorationHandles.Clear();
        gripWindow.Destroy();
        foreach (Display display in displays.Values) display.Layer.Destroy();
        displays.Clear();
    }
}
