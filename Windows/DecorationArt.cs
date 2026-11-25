using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Snowglow.Windows;

internal readonly record struct PlacedDecoration(Decoration Item, Box Bounds);

internal static class DecorationArt
{
    private static readonly Pen Wire = new(SnowArt.Ink(0xFF17382E), 1.4);
    private static readonly uint[] Classic = [0xFFFF7378, 0xFFFFC76F, 0xFF6DE6A8, 0xFF9AB1FF];
    private static readonly uint[] Winter = [0xFF71DBFF, 0xFFC8EFFF, 0xFF8FAAFF, 0xFFEBFCFF];
    private static readonly uint[] Gold = [0xFFFFCD73, 0xFFFFE5AA, 0xFFFFA758];
    private static readonly string[] Surprises = ["star", "gift", "snow", "lantern", "moon", "decorations", "tree"];

    internal static string Name(DecorationKind kind) => kind switch
    {
        DecorationKind.Tree => "圣诞树", DecorationKind.Lights => "窗边彩灯",
        DecorationKind.Lantern => "提灯", DecorationKind.Gift => "礼物", _ => "倒数日历"
    };

    internal static string Key(DecorationKind kind) => kind.ToString().ToLowerInvariant();
    internal static (float Width, float Height) Size(DecorationKind kind) => kind switch
    {
        DecorationKind.Tree => (154, 185), DecorationKind.Lights => (260, 54),
        DecorationKind.Lantern => (80, 100), DecorationKind.Gift => (84, 82), _ => (272, 225)
    };

    internal static int AvailableDoors(DateTime time) => time.Month == 12 ? Math.Min(time.Day, 25) : 0;

    internal static void Paint(DrawingContext context, PlacedDecoration placed, double seconds)
    {
        var item = placed.Item;
        var box = placed.Bounds;
        if (!box.HasArea) return;
        var rect = new Rect(box.Left, box.Top, box.Width, box.Height);
        context.PushTransform(new RotateTransform(item.Rotation, box.MidX, (box.Top + box.Bottom) / 2));
        if (item.Kind == DecorationKind.Lights)
        {
            Lights(context, rect, item, seconds);
        }
        else
        {
            context.DrawImage(Artwork.Image($"Decorations.{Key(item.Kind)}.png"), rect);
            if (item.Kind == DecorationKind.Calendar)
                Calendar(context, rect, item);
        }
        context.Pop();
    }

    private static void Lights(DrawingContext context, Rect rect, Decoration item, double seconds)
    {
        var colors = item.Palette switch { 1 => Winter, 2 => Gold, _ => Classic };
        int count = Math.Clamp((int)(rect.Width / Math.Clamp(17 * item.Scale, 9, 34)), 2, 96);
        var previous = new Point(rect.X, rect.Y + 7 * item.Scale);
        for (int index = 0; index <= count; index++)
        {
            double fraction = (double)index / count;
            var point = new Point(rect.X + fraction * rect.Width,
                rect.Y + 7 * item.Scale + Math.Sin(fraction * Math.PI) * Math.Min(17 * item.Scale, rect.Height * .42));
            if (index != 0) context.DrawLine(Wire, previous, point);
            previous = point;
            var bulb = new Point(point.X, point.Y + item.Scale * 4);
            uint color = colors[index % colors.Length];
            int shade = item.LightEffect switch
            {
                1 => 4 + (int)Math.Round(2 + 2 * Math.Sin(seconds * 3.3 + index * 1.8)),
                2 => (index + (int)(seconds * 7)) % 5 == 0 ? 10 : 4,
                _ => 10
            };
            context.DrawEllipse(SnowArt.Ink(((uint)(shade * 4) << 24) | (color & 0xFFFFFF)), null, bulb,
                item.Scale * 6, item.Scale * 7);
            context.DrawEllipse(SnowArt.Ink(((uint)(shade * 25) << 24) | (color & 0xFFFFFF)), null, bulb,
                item.Scale * 2.6, item.Scale * 3.8);
        }
    }

    private static void Calendar(DrawingContext context, Rect rect, Decoration item)
    {
        int available = AvailableDoors(DateTime.Now);
        for (int day = 1; day <= 25; day++)
        {
            bool opened = (item.Opened & (1 << (day - 1))) != 0;
            if (!opened && day > available) continue;
            int col = (day - 1) % 5, row = (day - 1) / 5;
            double sx = rect.Width / 272, sy = rect.Height / 225;
            var tile = new Rect(rect.X + (18 + col * 48) * sx, rect.Y + (53 + row * 31) * sy, 42 * sx, 25 * sy);
            context.DrawRoundedRectangle(SnowArt.Ink(opened ? 0xFF584B45u : 0xFF375663u), null, tile, 5 * sx, 5 * sy);
            if (opened)
                context.DrawImage(Artwork.Icon(Surprises[(day - 1) % Surprises.Length]),
                    new Rect(tile.X + 14 * sx, tile.Y + 5 * sy, 14 * sx, 14 * sy));
            else
            {
                var text = new FormattedText(day.ToString(CultureInfo.InvariantCulture), CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight, new Typeface("Segoe UI"), 10 * sy, SnowArt.Ink(0xFFFFE4B7), 1.0);
                context.DrawText(text, new Point(tile.X + (tile.Width - text.Width) / 2, tile.Y + (tile.Height - text.Height) / 2));
            }
        }
    }
}
