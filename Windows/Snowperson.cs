using System;
using System.Collections.Generic;
using System.Numerics;

namespace Snowglow.Windows;

internal enum SnowmanOutfit { Classic, Santa, Winter, Crown, Earmuffs, Antlers, Elf, None }
internal enum SnowmanFace { Smile, Happy, Sleepy, Surprised }
internal enum SnowmanScarf { Auto, Red, Green, Blue, Gold, None }

internal sealed class Snowball(int kind, float radius, Vector2 center)
{
    public readonly int Kind = kind;
    public readonly float Radius = radius;
    public Vector2 Center = center;
    public Vector2 Velocity;
    public float Rotation;
}

internal sealed class Snowperson(Vector2 feet, bool manual, SnowmanOutfit outfit)
{
    public Vector2 Feet = feet;
    public bool Manual = manual;
    public SnowmanOutfit Outfit = outfit;
    public SnowmanFace Face;
    public SnowmanScarf Scarf;
    public bool Arms = true;
    public bool Buttons = true;
    public string? Anchor;
    public float AnchorX = .5f;
    public bool Tumbled { get; private set; }
    public int Held = -1;
    public bool Dragging { get; set; }
    public IReadOnlyList<Snowball> Balls => balls;

    private Snowball[] balls = MakeBalls(3);

    private static Snowball[] MakeBalls(int count) => count == 2
        ? [new(0, 30, default), new(2, 18, default)]
        : [new(0, 30, default), new(1, 23, default), new(2, 16, default)];

    public void ApplyClothes(SnowOptions options, float floor)
    {
        Outfit = options.Outfit;
        Face = options.Face;
        Scarf = options.Scarf;
        Arms = options.Arms;
        Buttons = options.Buttons;
        if (balls.Length == options.Snowballs || Dragging) return;
        balls = MakeBalls(options.Snowballs);
        Tumbled = false;
        Held = -1;
        Pose(floor);
    }

    public void Pose(float supportY)
    {
        if (Tumbled) return;
        if (!Manual) Feet.Y = supportY - 1;
        balls[0].Center = Feet - new Vector2(0, 30);
        if (balls.Length == 3) balls[1].Center = Feet - new Vector2(0, 74);
        balls[^1].Center = Feet - new Vector2(0, balls.Length == 3 ? 106 : 70);
        foreach (Snowball ball in balls) ball.Rotation = 0;
    }

    public void ToggleTumble(float x, float width, float supportY, bool reducedMotion)
    {
        if (Tumbled)
        {
            Tumbled = false;
            Manual = false;
            Feet = new Vector2(Math.Clamp(x, 47, Math.Max(47, width - 47)), supportY - 1);
            Pose(supportY);
            return;
        }

        Tumbled = true;
        float direction = x <= Feet.X ? 1 : -1;
        float factor = reducedMotion ? .54f : 1;
        foreach (var ball in balls)
            ball.Velocity = (ball.Kind switch
            {
                0 => new Vector2(-direction * 90, -48),
                1 => new Vector2(direction * 31, -70),
                _ => new Vector2(direction * 155, -104)
            }) * factor;
    }

    public void FallFromWindow()
    {
        Anchor = null;
        Manual = false;
        Tumbled = true;
        foreach (var ball in balls)
            ball.Velocity = new Vector2(17 * ball.Kind - 15, 10 * ball.Kind);
    }

    public void Step(float delta, float width, float floor, bool reducedMotion)
    {
        if (!Tumbled)
        {
            Pose(floor);
            return;
        }

        for (int index = 0; index < balls.Length; index++)
        {
            if (index == Held) continue;
            Snowball ball = balls[index];
            bool atRest = ball.Center.Y >= floor - ball.Radius - 1 && Math.Abs(ball.Velocity.Y) < .1f;
            ball.Velocity.Y += 760 * delta;
            float dx = ball.Velocity.X * delta;
            ball.Center += new Vector2(dx, ball.Velocity.Y * delta);
            float right = Math.Max(ball.Radius, width - ball.Radius);
            if (ball.Center.X < ball.Radius || ball.Center.X > right)
            {
                ball.Center.X = Math.Clamp(ball.Center.X, ball.Radius, right);
                ball.Velocity.X *= -.45f;
            }
            if (ball.Center.Y >= floor - ball.Radius)
            {
                ball.Center.Y = floor - ball.Radius;
                ball.Velocity.Y = ball.Velocity.Y > 65 ? -ball.Velocity.Y * .24f : 0;
                ball.Velocity.X *= MathF.Exp(-delta * (atRest ? 3.1f : 1.1f));
                if (Math.Abs(ball.Velocity.X) < 1) ball.Velocity.X = 0;
            }
            if (!reducedMotion) ball.Rotation += dx / ball.Radius;
        }
    }
}

internal sealed class PlowPass(float width, int direction)
{
    public readonly int Direction = direction;
    public readonly float Speed = Math.Clamp(width / 6.8f, 160, 310);
    public float Blade { get; private set; } = direction > 0 ? -14 : width + 14;
    public float Previous { get; private set; } = direction > 0 ? -14 : width + 14;
    public float Distance { get; private set; }

    public void Step(float delta)
    {
        Previous = Blade;
        Distance += Speed * delta;
        Blade += Direction * Speed * delta;
    }

    public bool Hits(Snowball ball, float floor)
    {
        float x = Math.Clamp(ball.Center.X, Math.Min(Previous, Blade) - 3, Math.Max(Previous, Blade) + 3);
        float y = Math.Clamp(ball.Center.Y, floor - 24, floor);
        return Vector2.DistanceSquared(ball.Center, new Vector2(x, y)) <= ball.Radius * ball.Radius;
    }

    public bool Finished(float width) => Blade < -118 && Direction < 0 || Blade > width + 118 && Direction > 0;
}

internal sealed class PushedSnowperson
{
    public Snowperson Person { get; }
    private readonly int direction;
    private readonly float speed;
    private float blade;
    private float time;

    public PushedSnowperson(Snowperson person, PlowPass pass)
    {
        Person = person;
        direction = pass.Direction;
        speed = pass.Speed;
        blade = pass.Blade;
        foreach (Snowball ball in person.Balls)
            ball.Velocity = new Vector2(0, -44 - ball.Kind * 37);
    }

    public bool Step(float delta, PlowPass? pass, float width, float floor, bool reducedMotion)
    {
        time += delta;
        blade = pass?.Direction == direction ? pass.Blade : blade + direction * speed * delta;
        float lead = 0;
        bool visible = false;
        foreach (Snowball ball in Person.Balls)
        {
            float previousX = ball.Center.X;
            float edge = blade + direction * (ball.Radius + lead * Math.Min(1, time / .38f));
            float coast = ball.Center.X + direction * speed * .70f * delta;
            ball.Center.X = direction * Math.Max(direction * edge, direction * coast);
            lead += ball.Radius * 1.85f;

            ball.Velocity.Y += delta * 820;
            ball.Center.Y += ball.Velocity.Y * delta;
            if (ball.Center.Y >= floor - ball.Radius)
            {
                ball.Center.Y = floor - ball.Radius;
                ball.Velocity.Y = ball.Velocity.Y > 72 ? -ball.Velocity.Y * .24f : 0;
            }
            if (!reducedMotion) ball.Rotation += (ball.Center.X - previousX) / ball.Radius;
            visible |= direction > 0 ? ball.Center.X - 56 < width : ball.Center.X + 56 > 0;
        }
        return visible;
    }
}
