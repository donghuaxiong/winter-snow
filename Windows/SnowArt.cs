using System;
using System.Collections.Generic;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;

namespace Snowglow.Windows;

internal static class SnowArt
{
    private sealed class ShelfDrawing
    {
        public int Version = -1;
        public Box Frame;
        public float Radius;
        public List<Span>? Visible;
        public StreamGeometry? Shape;
    }

    private static readonly ConditionalWeakTable<Shelf, ShelfDrawing> Cache = new();
    private static readonly Dictionary<uint, SolidColorBrush> BrushesByColor = new();
    private static readonly Dictionary<(uint, double), Pen> Pens = new();
    private static readonly Brush[] FlakeInk = BuildFlakeInk();
    private static readonly Brush Powder = Ink(0xC5E6F4FF);
    private static readonly Brush SnowBank = Freeze(new LinearGradientBrush(
        Color.FromRgb(251, 253, 255), Color.FromRgb(170, 198, 226), 90));
    private static readonly Brush BallFill = BuildBallFill();

    public static void Paint(DrawingContext context, SnowScene scene, bool dim, double time)
    {
        Rect viewport = new(0, 0, scene.Monitor.Width, scene.Monitor.Height);

        int clips = 0;
        if (scene.Taskbar is { } dock) { ClipOutside(context, viewport, dock); clips++; }
        if (scene.SettingsCover is { } settings) { ClipOutside(context, viewport, settings); clips++; }
        if (dim) context.DrawRectangle(Ink(0x4D071526), null, viewport);

        if (scene.Flakes.Count > 0)
        {
            foreach (Box window in scene.FlakeCovers) ClipOutside(context, viewport, window);
            foreach (Flake flake in scene.Flakes)
            {
                if (flake.Position.Y + flake.Radius < 0 || flake.Position.Y - flake.Radius > viewport.Bottom) continue;
                int shade = Math.Clamp((int)(flake.Opacity * 10), 0, FlakeInk.Length - 1);
                context.DrawEllipse(FlakeInk[shade], null, PointAt(flake.Position), flake.Radius, flake.Radius);
            }
            foreach (Box _ in scene.FlakeCovers) context.Pop();
        }

        foreach (Shelf shelf in scene.Shelves)
        {
            StreamGeometry? shape = BankShape(shelf);
            if (shape is not null)
            {
                if (scene.ShowIcicles && !shelf.IsFloor) DrawIcicles(context, shelf);
                context.DrawGeometry(SnowBank, null, shape);
            }
        }
        foreach (PlacedDecoration item in scene.Decorations)
            DecorationArt.Paint(context, item, time);
        if (scene.Person is { } person)
            DrawSnowperson(context, person, showShadow: !person.Tumbled);
        if (scene.Plow is { } pass)
            DrawPlow(context, pass, scene.FloorY, scene.PlowLoad);
        foreach (PushedSnowperson wreck in scene.Wrecks)
            DrawSnowperson(context, wreck.Person, showShadow: false);
        foreach (SnowGrain grain in scene.Grains)
        {
            if (grain.Slide is null)
                context.DrawEllipse(Powder, null, PointAt(grain.Position), grain.Radius, grain.Radius * .86);
            else DrawCornerClump(context, grain);
        }

        for (int i = 0; i < clips; i++) context.Pop();
    }

    private static void DrawCornerClump(DrawingContext context, SnowGrain grain)
    {
        double half = grain.ClumpWidth / 2;
        double radius = grain.Radius;
        context.PushTransform(new TranslateTransform(grain.Position.X, grain.Position.Y));
        if (grain.Angle != 0) context.PushTransform(new RotateTransform(grain.Angle * 180 / Math.PI));
        context.DrawEllipse(SnowBank, null, new Point(-half * .14, 0), half * .85, radius);
        context.DrawEllipse(SnowBank, null, new Point(half * .54, radius * .12), half * .46, radius * .72);
        if (grain.Angle != 0) context.Pop();
        context.Pop();
    }

    private static void DrawIcicles(DrawingContext context, Shelf shelf)
    {
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            foreach (Span span in shelf.Visible)
            {
                int first = (int)Math.Ceiling((span.Left - shelf.Frame.Left + 8) / 33);
                for (float x = shelf.Frame.Left + first * 33; x < span.Right - 8; x += 33)
                {
                    float depth = shelf.Snow.At(x - shelf.Frame.Left);
                    if (depth < 3) continue;
                    float y = shelf.TopAt(x);
                    double length = Math.Clamp(depth * (.76 + .24 * Math.Sin((x - shelf.Frame.Left) * .13)), 2, 17);
                    path.BeginFigure(new Point(x - 2.1, y - 1), true, true);
                    path.QuadraticBezierTo(new Point(x - 1.5, y + length * .53), new Point(x + .5, y + length), true, false);
                    path.QuadraticBezierTo(new Point(x + 1, y + length * .35), new Point(x + 1.8, y - .8), true, false);
                }
            }
        }
        context.DrawGeometry(Ink(0xD6B9E4F9), null, geometry);
    }

    private static void ClipOutside(DrawingContext context, Rect viewport, Box cover)
    {
        Rect overlap = Rect.Intersect(viewport, new Rect(cover.Left, cover.Top, cover.Width, cover.Height));
        if (overlap.IsEmpty) { context.PushClip(new RectangleGeometry(viewport)); return; }
        context.PushClip(new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(viewport), new RectangleGeometry(overlap)));
    }

    private static StreamGeometry? BankShape(Shelf shelf)
    {
        ShelfDrawing drawing = Cache.GetValue(shelf, static _ => new ShelfDrawing());
        if (drawing.Version == shelf.Snow.Version && drawing.Frame == shelf.Frame &&
            drawing.Radius == shelf.Radius && drawing.Visible == shelf.Visible)
            return drawing.Shape;

        drawing.Version = shelf.Snow.Version;
        drawing.Frame = shelf.Frame;
        drawing.Radius = shelf.Radius;
        drawing.Visible = shelf.Visible;
        var path = new StreamGeometry();
        bool hasSnow = false;
        using (StreamGeometryContext geometry = path.Open())
        {
            var points = new List<Point>();
            foreach (Span span in shelf.Visible)
            {
                for (float x = span.Left; x <= span.Right + .001f; x = Math.Min(span.Right, x + 5))
                {
                    float local = x - shelf.Frame.Left;
                    float height = shelf.Snow.At(local);
                    if (!shelf.IsFloor)
                    {
                        float edge = Math.Clamp(Math.Min(x - span.Left, span.Right - x) / 9, 0, 1);
                        height *= edge * edge * (3 - 2 * edge);
                    }
                    bool last = x >= span.Right - .001f;
                    if (height > .24f)
                        points.Add(new Point(x, shelf.TopAt(x) - height));
                    if ((height <= .24f || last) && points.Count > 0)
                    {
                        if (points.Count > 1 || height > .6f)
                        {
                            hasSnow = true;
                            AddBank(geometry, points, span, shelf);
                        }
                        points.Clear();
                    }
                    if (last) break;
                }
            }
        }
        path.Freeze();
        drawing.Shape = hasSnow ? path : null;
        return drawing.Shape;
    }

    private static void AddBank(StreamGeometryContext path, List<Point> points, Span range, Shelf shelf)
    {
        Point first = points[0], last = points[^1];
        double start = Math.Max(range.Left, first.X - 4);
        double end = Math.Min(range.Right, last.X + 4);
        double startY = shelf.TopAt((float)start), endY = shelf.TopAt((float)end);
        path.BeginFigure(new Point(start, shelf.IsFloor && start == range.Left ? first.Y : startY), true, true);
        path.QuadraticBezierTo(new Point(start + 2, first.Y + .8), first, true, false);
        for (int i = 0; i + 1 < points.Count; i++)
        {
            Point a = points[i], b = points[i + 1];
            path.BezierTo(new Point(a.X + (b.X - a.X) * .37, a.Y),
                new Point(b.X - (b.X - a.X) * .37, b.Y), b, true, false);
        }
        path.QuadraticBezierTo(new Point(end - 2, last.Y + .8), new Point(end, shelf.IsFloor && end == range.Right ? last.Y : endY), true, false);
        double contact = shelf.IsFloor ? 1.4 : 1.0;
        path.LineTo(new Point(end, endY + contact), true, false);
        if (shelf.Radius > 0)
            for (int i = points.Count - 1; i >= 0; i--)
                path.LineTo(new Point(points[i].X, shelf.TopAt((float)points[i].X) + contact), true, false);
        path.LineTo(new Point(start, startY + contact), true, false);
    }

    private static void DrawSnowperson(DrawingContext context, Snowperson person, bool showShadow)
    {
        if (showShadow)
            context.DrawEllipse(Ink(0x4520415F), null, PointAt(person.Feet), 27, 2.5);
        foreach (Snowball ball in person.Balls) DrawBall(context, ball, person);
    }

    private static void DrawBall(DrawingContext context, Snowball ball, Snowperson person)
    {
        Point center = PointAt(ball.Center);
        context.PushTransform(new TranslateTransform(center.X, center.Y));
        if (ball.Rotation != 0)
            context.PushTransform(new RotateTransform(ball.Rotation * 180 / Math.PI));

        bool clothes = ball.Kind == (person.Balls.Count == 3 ? 1 : 0);
        if (clothes && person.Arms)
        {
            Line(context, 0xFF6C4936, 2.8, (-17, 4), (-34, -8), (-42, -17));
            Line(context, 0xFF8C6448, 1.8, (-34, -8), (-44, -10));
            Line(context, 0xFF6C4936, 2.8, (18, 3), (34, -8), (45, -16));
            Line(context, 0xFF8C6448, 1.8, (34, -8), (35, -17));
        }
        context.DrawEllipse(BallFill, null, new Point(0, 0), ball.Radius, ball.Radius);
        for (int i = 0; i < 7; i++)
        {
            double r = ball.Radius * (.26 + .57 * ((i * 17 % 11) / 10d));
            double theta = i * 2.34;
            Dot(context, 0x45FFFFFF, Math.Cos(theta) * r, Math.Sin(theta) * r, 1.15 + .42 * (i % 3));
        }
        if (clothes)
        {
            if (person.Buttons)
                for (int i = 0; i < 3; i++)
                    Dot(context, 0xFF29374A, 1.5 * Math.Sin(i), 1 + i * 7.3, 1.75);
            uint scarf = person.Scarf switch
            {
                SnowmanScarf.Green => 0xFF2E8270, SnowmanScarf.Blue => 0xFF356FA8,
                SnowmanScarf.Gold => 0xFFE4A840, SnowmanScarf.Red => 0xFFC53450,
                _ => person.Outfit switch
                {
                    SnowmanOutfit.Winter => 0xFF356FA8,
                    SnowmanOutfit.Classic => 0xFF2E8270,
                    _ => 0xFFC53450
                }
            };
            if (person.Scarf != SnowmanScarf.None)
            {
                double y = person.Balls.Count == 2 ? -7 : 0;
                Line(context, scarf, 5.6, (6, y - 14), (10, y - 8), (10.5, y + 2));
                Line(context, scarf, 5.5, (-13, y - 19), (-6, y - 16), (4, y - 15.5), (12, y - 18));
                Line(context, 0xA9FFE4DB, 1.1, (-12, y - 20), (-6, y - 17.3), (4, y - 16.8), (11, y - 19));
            }
        }
        if (ball.Kind == 2)
        {
            for (int side = -1; side <= 1; side += 2)
                if (person.Face is SnowmanFace.Sleepy or SnowmanFace.Happy)
                {
                    double x = side * 5.2, bend = person.Face == SnowmanFace.Happy ? -1.7 : 1;
                    Line(context, 0xFF253247, 1.15, (x - 2.1, -3.0), (x, -3.0 + bend), (x + 2.1, -3.0));
                }
                else Dot(context, 0xFF253247, side * 5.2, -3.1, person.Face == SnowmanFace.Surprised ? 1.85 : 1.55);
            context.DrawEllipse(Ink(0x80F2898D), null, new Point(-8.4, 2.4), 2.6, 1.7);
            context.DrawEllipse(Ink(0x80F2898D), null, new Point(8.4, 2.4), 2.6, 1.7);
            Polygon(context, 0xFFF18F42, (-2, 0), (8.2, 2.3), (-1.6, 4.2));
            if (person.Face == SnowmanFace.Surprised)
                context.DrawEllipse(Ink(0xFF364657), null, new Point(0, 8), 2.3, 3.0);
            else
                for (int i = -2; i <= 2; i++)
                    Dot(context, 0xFF364657, i * 2.1, 8.6 - i * i * .5, .72);
            DrawHat(context, person.Outfit);
        }
        if (ball.Rotation != 0) context.Pop();
        context.Pop();
    }

    private static void DrawHat(DrawingContext context, SnowmanOutfit outfit)
    {
        if (outfit == SnowmanOutfit.Classic)
        {
            Round(context, 0xFF253148, -12, -32, 24, 20, 3);
            Round(context, 0xFF41637E, -11, -19, 22, 4, 1);
            Round(context, 0xFF1B273A, -17, -15, 34, 5, 2);
        }
        else if (outfit == SnowmanOutfit.Winter)
        {
            context.DrawEllipse(Ink(0xFF357AB4), null, new Point(0, -19), 14, 12);
            Dot(context, 0xFFF4FAFF, 0, -31, 4.2);
            Round(context, 0xFFDDEBFA, -15, -19, 30, 6.5, 2.4);
            for (int i = -11; i <= 11; i += 4)
                Line(context, 0xFF9BBFDA, .8, (i, -17), (i, -14));
        }
        else if (outfit == SnowmanOutfit.Santa)
        {
            context.DrawEllipse(Ink(0xFFD63C56), null, new Point(-3, -22), 12.4, 12.0);
            Polygon(context, 0xFFD63C56, (-11, -21), (1, -32), (14, -27), (16, -21), (4, -19));
            Round(context, 0xFFFBFDFF, -15, -17.5, 29, 5.7, 2.8);
            Dot(context, 0xFFF8FBFF, 15.4, -22.9, 4.1);
        }
        else if (outfit == SnowmanOutfit.Crown)
        {
            Polygon(context, 0xFFE8A635, (-14, -29), (-6, -24), (0, -34), (6, -24), (14, -29), (11, -13), (-11, -13));
            Round(context, 0xFFF4C565, -11, -19, 22, 5, 1.2);
            Dot(context, 0xFFB53D61, 0, -20, 2.1);
        }
        else if (outfit == SnowmanOutfit.Earmuffs)
        {
            Line(context, 0xFFC34F84, 3, (-13, -8), (-11, -19), (-6, -24), (5, -24), (11, -19), (13, -8));
            Dot(context, 0xFFF3B3C6, -14, -9, 5);
            Dot(context, 0xFFF3B3C6, 14, -9, 5);
        }
        else if (outfit == SnowmanOutfit.Antlers)
        {
            for (int side = -1; side <= 1; side += 2)
            {
                Line(context, 0xFF875B36, 2.5, (6 * side, -14), (12 * side, -22), (13 * side, -32), (17 * side, -36));
                Line(context, 0xFFB3885A, 2, (12 * side, -25), (20 * side, -27), (21 * side, -31));
                Line(context, 0xFFB3885A, 2, (13 * side, -32), (8 * side, -35));
            }
        }
        else if (outfit == SnowmanOutfit.Elf)
        {
            Polygon(context, 0xFF268366, (-15, -15), (-7, -29), (5, -35), (14, -37), (9, -27), (15, -15));
            Round(context, 0xFFEAB34E, -15, -18, 30, 6, 2.5);
            Dot(context, 0xFFF7D789, 14, -37, 3.1);
        }
    }

    private static void DrawPlow(DrawingContext context, PlowPass pass, float floor, float load)
    {
        context.PushTransform(new TranslateTransform(pass.Blade, floor));
        context.PushTransform(new ScaleTransform(pass.Direction, 1));
        context.DrawEllipse(Ink(0x50314960), null, new Point(-40, -.5), 48, 3);
        Round(context, 0xFF25394F, -84, -16, 66, 15, 7.5);
        Round(context, 0xFF4B6076, -81, -14, 60, 11, 5.5);
        for (int i = 0; i < 4; i++)
        {
            double x = -75 + i * 16;
            Dot(context, 0xFFABBED5, x, -8.4, 5);
            Dot(context, 0xFFE4EDF7, x, -8.7, 3.5);
            double theta = pass.Distance / 4.8 + i;
            Dot(context, 0xFF768FAC, x + 2.3 * Math.Cos(theta), -8.5 + 2.3 * Math.Sin(theta), .9);
        }
        Round(context, 0xFFA86E32, -72, -48, 40, 30, 4.5);
        Round(context, 0xFFFFCF66, -70, -46, 36, 26, 3.4);
        Round(context, 0xFFF8FBF4, -67, -44, 29, 17, 2.5);
        Round(context, 0xFF87BFE1, -65, -42, 25, 13, 1.9);
        Polygon(context, 0xA5F4FCFF, (-64, -41), (-54, -41), (-61, -30), (-64, -30));
        Round(context, 0xFFA87133, -86, -27, 71, 13.5, 4.3);
        Round(context, 0xFFFFCC55, -84, -25, 67, 9.2, 3.8);
        Round(context, 0xFFFFF4D7, -25, -23.7, 5.5, 3.5, 1.2);
        Round(context, 0xFFCB5D53, -82, -23.7, 5, 3.5, 1.2);
        Round(context, 0xFFF8A240, -58, -53, 9, 6, 2.5);
        byte glow = (byte)(95 + 120 * (.5 + .5 * Math.Sin(pass.Distance / 14)));
        context.DrawEllipse(FlakeInk[glow / 27], null, new Point(-53.5, -51), 2.45, 2);
        Line(context, 0xFF65798F, 3.3, (-17, -16), (-8, -10), (-3, -6));
        Polygon(context, 0xFFA2BAD2, (-8.3, -23), (-4.6, -22), (-3.4, -11), (3.3, -3), (1, -1), (-5.7, -3.5), (-9, -12));
        Line(context, 0xFFE8F2FD, 1.2, (-5.3, -22), (-4.5, -13), (-1.0, -7), (2.4, -3.6));
        if (load > .6)
            SnowMound(context, load);
        context.Pop();
        context.Pop();
    }

    private static void SnowMound(DrawingContext context, float lift)
    {
        var path = new StreamGeometry();
        using (var g = path.Open())
        {
            g.BeginFigure(new Point(0, 0), true, true);
            g.BezierTo(new Point(2, -lift), new Point(7, -lift), new Point(10, -lift * .83), true, false);
            g.QuadraticBezierTo(new Point(16 + lift * .4, -lift * .5), new Point(22 + lift, 0), true, false);
        }
        context.DrawGeometry(SnowBank, null, path);
    }

    private static void Round(DrawingContext context, uint color, double x, double y, double w, double h, double radius) =>
        context.DrawRoundedRectangle(Ink(color), null, new Rect(x, y, w, h), radius, radius);

    private static void Dot(DrawingContext context, uint color, double x, double y, double size) =>
        context.DrawEllipse(Ink(color), null, new Point(x, y), size, size);

    private static void Polygon(DrawingContext context, uint color, params (double X, double Y)[] points)
    {
        var path = new StreamGeometry();
        using (var g = path.Open())
        {
            g.BeginFigure(new Point(points[0].X, points[0].Y), true, true);
            for (int i = 1; i < points.Length; i++)
                g.LineTo(new Point(points[i].X, points[i].Y), true, false);
        }
        context.DrawGeometry(Ink(color), null, path);
    }

    private static void Line(DrawingContext context, uint color, double width, params (double X, double Y)[] points)
    {
        if (!Pens.TryGetValue((color, width), out Pen? pen))
        {
            pen = Freeze(new Pen(Ink(color), width)
            {
                StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round
            });
            Pens.Add((color, width), pen);
        }
        for (int i = 0; i + 1 < points.Length; i++)
            context.DrawLine(pen, new Point(points[i].X, points[i].Y), new Point(points[i + 1].X, points[i + 1].Y));
    }

    internal static SolidColorBrush Ink(uint value)
    {
        if (!BrushesByColor.TryGetValue(value, out SolidColorBrush? brush))
        {
            Color color = Color.FromArgb((byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value);
            brush = Freeze(new SolidColorBrush(color));
            BrushesByColor.Add(value, brush);
        }
        return brush;
    }

    private static Brush[] BuildFlakeInk()
    {
        var result = new Brush[10];
        for (int i = 0; i < result.Length; i++)
            result[i] = Freeze(new SolidColorBrush(Color.FromArgb((byte)(54 + i * 20), 232, 246, 255)));
        return result;
    }

    private static Brush BuildBallFill()
    {
        var gradient = new RadialGradientBrush
        {
            GradientOrigin = new Point(.29, .25),
            Center = new Point(.42, .37),
            RadiusX = .66, RadiusY = .68
        };
        gradient.GradientStops.Add(new GradientStop(Colors.White, 0));
        gradient.GradientStops.Add(new GradientStop(Color.FromRgb(241, 249, 255), .42));
        gradient.GradientStops.Add(new GradientStop(Color.FromRgb(207, 224, 244), .80));
        gradient.GradientStops.Add(new GradientStop(Color.FromRgb(151, 184, 219), 1));
        return Freeze(gradient);
    }

    private static T Freeze<T>(T resource) where T : Freezable { resource.Freeze(); return resource; }
    private static Point PointAt(Vector2 value) => new(value.X, value.Y);
}
