using System;
using System.Collections.Generic;

namespace Snowglow.Windows;

internal sealed class SnowPack(float width, bool floor)
{
    private const float Spacing = 6;
    private readonly float depth = floor ? 25 : 14;
    private float[] heights = new float[CountFor(width)];
    private float nextLeftSpill, nextRightSpill;

    public float Width { get; private set; } = width;
    public int Version { get; private set; }
    public int Count => heights.Length;
    public float Level(int index) => heights[index];
    public float Column(int index) => Math.Min(Width, (index + 0.5f) * Spacing);
    public bool DeepEnough
    {
        get
        {
            float sum = 0;
            int covered = 0;
            foreach (float value in heights)
            {
                sum += value;
                if (value >= 3.5f) covered++;
            }
            return sum >= 7.5f * heights.Length && covered * 5 >= heights.Length * 3;
        }
    }

    private static int CountFor(float width) => Math.Max(1, (int)MathF.Ceiling(width / Spacing));

    public void Resize(float width)
    {
        if (Width == width) return;
        Width = width;
        Array.Resize(ref heights, CountFor(width));
        Version++;
    }

    public float At(float x)
    {
        float position = Math.Clamp(x / Spacing - .5f, 0, heights.Length - 1);
        int index = (int)position;
        float result = heights[index] + (heights[Math.Min(index + 1, heights.Length - 1)] - heights[index]) * (position - index);
        if (floor) return result;
        float taper = Math.Clamp(Math.Min(x, Width - x) / 16, 0, 1);
        return result * taper * taper * (3 - 2 * taper);
    }

    public void Land(float x, float mass)
    {
        int center = (int)Math.Clamp(x / Spacing, 0, heights.Length - 1);
        int start = Math.Max(0, center - 2);
        int end = Math.Min(heights.Length - 1, center + 2);
        float totalWeight = 0;
        for (int i = start; i <= end; i++) totalWeight += 3 - Math.Abs(i - center);
        for (int i = start; i <= end; i++)
        {
            float terrain = .88f + .078f * MathF.Sin(Column(i) / 37) + .038f * MathF.Sin(Column(i) / 14);
            float capacity = depth * terrain;
            heights[i] = Math.Min(capacity, heights[i] + mass * (3 - Math.Abs(i - center)) / totalWeight);
        }
        Version++;
    }

    public float RemoveInSpan(float first, float last, float leave)
    {
        if (last < 0 || first > Width || last < first) return 0;
        int start = Math.Clamp((int)(first / Spacing), 0, heights.Length - 1);
        int end = Math.Clamp((int)(last / Spacing), 0, heights.Length - 1);
        float removed = 0;
        for (int i = start; i <= end; i++)
        {
            if (Column(i) < first || Column(i) > last || heights[i] <= leave) continue;
            removed += heights[i] - leave;
            heights[i] = leave;
        }
        if (removed > 0) Version++;
        return removed;
    }

    public float Sweep(float x, float horizontalSpeed)
    {
        int i = (int)Math.Clamp(x / Spacing, 0, heights.Length - 1);
        float mass = Math.Min(heights[i] * .58f, .6f + Math.Abs(horizontalSpeed) * .008f);
        if (mass <= .04f) return 0;
        heights[i] -= mass;
        Version++;
        return mass;
    }

    public float SpillFromCorner(bool left, float now)
    {
        if (floor || heights.Length < 5 || now < (left ? nextLeftSpill : nextRightSpill)) return 0;
        int outer = left ? 0 : heights.Length - 1;
        int inward = left ? 1 : -1;
        float edge = heights[outer];
        float shoulder = heights[outer + inward] * .62f + heights[outer + inward * 2] * .38f;
        if (edge < depth * .33f || shoulder < depth * .56f || edge * .38f + shoulder * .62f < depth * .52f) return 0;

        float mass = Slice(outer, .42f) + Slice(outer + inward, .28f) + Slice(outer + inward * 2, .15f);
        float cooldown = 3.4f + (Width % 59) / 36f + (left ? 0 : .45f);
        if (left) nextLeftSpill = now + cooldown;
        else nextRightSpill = now + cooldown;
        Version++;
        return mass;

        float Slice(int index, float portion)
        {
            float amount = Math.Min(heights[index] * portion, Math.Max(0, heights[index] - depth * .27f));
            heights[index] -= amount;
            return amount;
        }
    }

    public void DepositClump(float x, float mass)
    {
        int center = Math.Clamp((int)(x / Spacing), 0, heights.Length - 1);
        int first = Math.Max(0, center - 2), end = Math.Min(heights.Length - 1, center + 2);
        float weights = 0;
        for (int i = first; i <= end; i++) weights += 3 - Math.Abs(i - center);
        float remaining = mass;
        for (int i = first; i <= end; i++)
            remaining -= Place(i, mass * (3 - Math.Abs(i - center)) / weights);
        for (int offset = 0; offset < heights.Length && remaining > .001f; offset++)
        {
            if (center - offset >= 0) remaining -= Place(center - offset, remaining);
            if (offset > 0 && center + offset < heights.Length) remaining -= Place(center + offset, remaining);
        }
        Version++;

        float Place(int index, float amount)
        {
            float room = Math.Min(amount, Math.Max(0, depth - heights[index]));
            heights[index] += room;
            return room;
        }
    }

    public void Settle()
    {
        float left = heights[0];
        bool changed = false;
        for (int i = 1; i < heights.Length; i++)
        {
            float right = heights[i];
            float slope = left - right;
            if (Math.Abs(slope) > .025f)
            {
                float flow = slope * .075f + MathF.CopySign(Math.Max(0, Math.Abs(slope) - 1.5f) * .18f, slope);
                heights[i - 1] -= flow;
                heights[i] += flow;
                changed = true;
            }
            left = right;
        }
        if (changed) Version++;
    }

    public void Clear()
    {
        Array.Clear(heights);
        nextLeftSpill = nextRightSpill = 0;
        Version++;
    }
}

internal sealed class Shelf(Box frame, bool floor)
{
    public Box Frame = frame;
    public readonly SnowPack Snow = new(frame.Width, floor);
    public readonly bool IsFloor = floor;
    public List<Span> Visible = [new(frame.Left, frame.Right)];
    public float Radius;
    public float LastVelocity;
    public double LastShake = -1;
    public bool LeftOverflow, RightOverflow;

    public bool Supports(float x) => x >= Frame.Left && x <= Frame.Right && Visible.Exists(span => span.Contains(x));

    public float TopAt(float x)
    {
        float distance = Math.Max(0, Math.Min(x - Frame.Left, Frame.Right - x));
        if (distance >= Radius) return Frame.Top;
        float rim = Radius - distance;
        return Frame.Top + Radius - MathF.Sqrt(Math.Max(0, Radius * Radius - rim * rim));
    }

    public Box? OverflowRoute(bool left, Box viewport, float floor)
    {
        if (IsFloor || Radius <= 0 || Frame.Top + Radius + 7 >= floor) return null;
        float edge = left ? Frame.Left : Frame.Right;
        float inside = edge + (left ? 1 : -1) * Math.Max(20, Radius + 4);
        float outside = edge + (left ? -6 : 6);
        if (outside < viewport.Left || outside >= viewport.Right || !Visible.Exists(span => span.Contains(edge) && span.Contains(inside)))
            return null;
        return new Box(Math.Min(inside, outside), Frame.Top - 5, Math.Max(inside, outside), Frame.Top + Radius + 7);
    }

    public static List<Span> Exposed(Box frame, Box viewport, List<Box> nearer)
    {
        List<Span> spans = [new(Math.Max(frame.Left, viewport.Left), Math.Min(frame.Right, viewport.Right))];
        foreach (Box cover in nearer)
        {
            if (cover.Top > frame.Top + 2 || cover.Bottom < frame.Top - 2) continue;
            for (int i = spans.Count - 1; i >= 0; i--)
            {
                Span span = spans[i];
                if (cover.Left >= span.Right || cover.Right <= span.Left) continue;
                spans.RemoveAt(i);
                if (cover.Right < span.Right) spans.Insert(i, new Span(cover.Right, span.Right));
                if (cover.Left > span.Left) spans.Insert(i, new Span(span.Left, cover.Left));
            }
        }
        spans.RemoveAll(span => span.Length < 5);
        return spans;
    }
}
