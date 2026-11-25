using System;
using System.Numerics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Snowglow.Windows;

internal sealed class Overlay : Window
{
    private readonly bool passthrough;
    private nint handle;
    private Box? placed;
    private bool closed;

    public Overlay(FrameworkElement drawing, bool passthrough)
    {
        this.passthrough = passthrough;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Focusable = false;
        Width = Height = 1;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        Content = drawing;
    }

    public void Place(Box pixels)
    {
        if (!IsVisible)
        {
            handle = new WindowInteropHelper(this).EnsureHandle();
            NativeDesktop.PrepareOverlay(handle, passthrough);
            NativeDesktop.PlaceOverlay(handle, pixels);
            Show();
            NativeDesktop.PrepareOverlay(handle, passthrough);
            NativeDesktop.PlaceOverlay(handle, pixels, raise: true);
        }
        else if (placed != pixels)
            NativeDesktop.PlaceOverlay(handle, pixels);
        placed = pixels;
    }

    public void Destroy()
    {
        if (!closed) Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        closed = true;
        base.OnClosed(e);
    }
}

internal sealed class WeatherVisual(SnowScene scene) : FrameworkElement
{
    public bool ShowFlakes { get; set; }
    public bool Dim { get; set; }
    public double Time { get; set; }

    protected override void OnRender(DrawingContext context)
    {
        if (ActualWidth < 1 || ActualHeight < 1) return;
        context.PushTransform(new ScaleTransform(ActualWidth / scene.Monitor.Width, ActualHeight / scene.Monitor.Height));
        SnowArt.Paint(context, scene, ShowFlakes, Dim, Time);
        context.Pop();
    }
}

internal sealed class SnowmanGrip : FrameworkElement
{
    private static readonly Brush HitInk = SnowArt.Ink(0x06FFFFFF);
    private Snowperson? snowman;
    private MonitorInfo? monitor;
    private Box frame;

    internal event Action<Vector2>? Grabbed;
    internal event Action<Vector2>? Moved;
    internal event Action? Dropped;
    internal event Action<Vector2>? Knocked;

    public SnowmanGrip()
    {
        Cursor = Cursors.Hand;
        Focusable = false;
    }

    public void Update(Snowperson person, MonitorInfo display, Box pixelFrame)
    {
        snowman = person;
        monitor = display;
        frame = pixelFrame;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext context)
    {
        if (snowman is null || monitor is null || ActualWidth < 1 || ActualHeight < 1) return;
        double scaleX = ActualWidth / frame.Width;
        double scaleY = ActualHeight / frame.Height;
        foreach (Snowball ball in snowman.Balls)
        {
            Vector2 point = monitor.ToPixel(ball.Center);
            double radius = (ball.Radius + 3) * monitor.Scale;
            context.DrawEllipse(HitInk, null,
                new Point((point.X - frame.Left) * scaleX, (point.Y - frame.Top) * scaleY), radius * scaleX, radius * scaleY);
        }
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        Cursor = Cursors.SizeAll;
        Grabbed?.Invoke(NativeDesktop.Cursor());
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        Moved?.Invoke(NativeDesktop.Cursor());
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        Moved?.Invoke(NativeDesktop.Cursor());
        Dropped?.Invoke();
        EndGesture();
        e.Handled = true;
    }

    public void EndGesture()
    {
        Cursor = Cursors.Hand;
        if (IsMouseCaptured) ReleaseMouseCapture();
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        if (IsMouseCaptured) return;
        Knocked?.Invoke(NativeDesktop.Cursor());
        e.Handled = true;
    }
}

internal sealed class DecorationGrip : FrameworkElement
{
    private static readonly Brush Hit = SnowArt.Ink(0x09FFFFFF);
    private static readonly Pen Edge = new(SnowArt.Ink(0xAA9BC7FF), 1.3) { DashStyle = DashStyles.Dash };
    internal event Action<Vector2>? Grabbed;
    internal event Action? Dropped;

    public DecorationGrip() { Cursor = Cursors.SizeAll; Focusable = false; }

    protected override void OnRender(DrawingContext context)
    {
        if (ActualWidth <= 2 || ActualHeight <= 2) return;
        context.DrawRoundedRectangle(Hit, Edge, new Rect(1, 1, ActualWidth - 2, ActualHeight - 2), 8, 8);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        Grabbed?.Invoke(NativeDesktop.Cursor());
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        Dropped?.Invoke();
        if (IsMouseCaptured) ReleaseMouseCapture();
        e.Handled = true;
    }
}
