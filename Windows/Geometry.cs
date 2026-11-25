using System;
using System.Numerics;

namespace Snowglow.Windows;

internal readonly record struct Box(float Left, float Top, float Right, float Bottom)
{
    public float Width => Right - Left;
    public float Height => Bottom - Top;
    public float MidX => (Left + Right) / 2;
    public bool HasArea => Width > 0 && Height > 0;
    public bool Contains(Vector2 point) => point.X >= Left && point.X < Right && point.Y >= Top && point.Y < Bottom;
    public Box Intersect(Box other) => new(Math.Max(Left, other.Left), Math.Max(Top, other.Top),
        Math.Min(Right, other.Right), Math.Min(Bottom, other.Bottom));
}

internal readonly record struct Span(float Left, float Right)
{
    public float Length => Right - Left;
    public bool Contains(float x) => x >= Left && x <= Right;
}

internal sealed record MonitorInfo(string Name, Box Pixels, float Scale, bool Primary)
{
    public float Width => Pixels.Width / Scale;
    public float Height => Pixels.Height / Scale;
    public Vector2 ToLocal(Vector2 point) =>
        new((point.X - Pixels.Left) / Scale, (point.Y - Pixels.Top) / Scale);
    public Box ToLocal(Box rect) =>
        new((rect.Left - Pixels.Left) / Scale, (rect.Top - Pixels.Top) / Scale,
            (rect.Right - Pixels.Left) / Scale, (rect.Bottom - Pixels.Top) / Scale);
    public Vector2 ToPixel(Vector2 point) =>
        new(Pixels.Left + point.X * Scale, Pixels.Top + point.Y * Scale);
}
