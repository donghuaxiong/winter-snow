using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Text;

namespace Snowglow.Windows;

internal readonly record struct WindowSample(nint Handle, Box Frame, bool Taskbar, float CornerRadius, string? Key);

internal static class NativeDesktop
{
    private const int ExStyle = -20;
    private const int ToolWindow = 0x80;
    private const int NoActivate = 0x08000000;
    private const int Transparent = 0x20;
    private const int AppWindow = 0x40000;
    private static readonly nint Topmost = new(-1);
    private static readonly uint OwnProcess = (uint)Environment.ProcessId;

    internal static void EnablePerMonitorDpi() => SetProcessDpiAwarenessContext(new nint(-4));

    internal static List<MonitorInfo> Monitors()
    {
        var result = new List<MonitorInfo>();
        EnumDisplayMonitors(0, 0, (nint handle, nint dc, ref NativeRect rect, nint data) =>
        {
            var info = new MONITORINFOEX { Size = Marshal.SizeOf<MONITORINFOEX>(), Device = string.Empty };
            if (!GetMonitorInfoW(handle, ref info))
                return true;

            float scale = GetDpiForMonitor(handle, 0, out uint dpi, out _) == 0 && dpi > 0 ? dpi / 96f : 1;
            result.Add(new MonitorInfo(info.Device, info.Monitor.Box, scale, (info.Flags & 1) != 0));
            return true;
        }, 0);
        return result;
    }

    internal static List<WindowSample> Windows(bool includeIdentity = false)
    {
        var result = new List<WindowSample>();
        var className = new StringBuilder(128);
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle) || IsIconic(handle))
                return true;
            GetWindowThreadProcessId(handle, out uint pid);
            if (pid == OwnProcess)
                return true;

            className.Clear();
            GetClassNameW(handle, className, className.Capacity);
            string kind = className.ToString();
            bool taskbar = kind is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";
            if (kind is "Progman" or "WorkerW" or "DV2ControlHost" or "#32768")
                return true;
            if (!taskbar)
            {
                int style = GetWindowLongW(handle, ExStyle);
                if ((style & ToolWindow) != 0 && (style & AppWindow) == 0)
                    return true;
                if (DwmGetWindowAttribute(handle, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0)
                    return true;
            }

            NativeRect native = default;
            if ((taskbar || DwmGetWindowAttribute(handle, 9, out native, Marshal.SizeOf<NativeRect>()) != 0)
                && !GetWindowRect(handle, out native))
                return true;
            var rect = native.Box;
            if (rect.Width >= 24 && rect.Height >= 20)
            {
                float radius = 0;
                if (!taskbar && !IsZoomed(handle) && OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000))
                {
                    DwmGetWindowAttribute(handle, 33, out int preference, sizeof(int));
                    radius = preference switch { 1 => 0, 3 => 4, _ => 8 };
                }
                result.Add(new WindowSample(handle, rect, taskbar, radius,
                    includeIdentity && !taskbar ? WindowKey(handle, pid, kind) : null));
            }
            return true;
        }, 0);
        return result;
    }

    internal static Vector2 Cursor()
    {
        GetCursorPos(out var point);
        return new Vector2(point.X, point.Y);
    }

    internal static bool PrimaryMouseDown => GetAsyncKeyState(0x01) < 0;
    internal static bool EscapeDown => GetAsyncKeyState(0x1B) < 0;
    internal static nint ForegroundWindow => GetForegroundWindow();
    internal static uint? LastInputStamp
    {
        get
        {
            var info = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() };
            return GetLastInputInfo(ref info) ? info.Time : null;
        }
    }
    internal static uint IdleMilliseconds(uint stamp) => unchecked((uint)Environment.TickCount - stamp);

    private static string? WindowKey(nint handle, uint pid, string className)
    {
        var title = new StringBuilder(256);
        if (GetWindowTextW(handle, title, title.Capacity) == 0) return null;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return $"{process.ProcessName}\u001f{className}\u001f{title}";
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or System.ComponentModel.Win32Exception) { return null; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo { public uint Size, Time; }

    internal static void PrepareOverlay(nint handle, bool clickThrough)
    {
        int style = GetWindowLongW(handle, ExStyle);
        style = (style | ToolWindow | NoActivate) & ~AppWindow;
        if (clickThrough) style |= Transparent;
        SetWindowLongW(handle, ExStyle, style);
    }

    internal static void PlaceOverlay(nint handle, Box bounds, bool raise = false)
    {
        int x = (int)MathF.Floor(bounds.Left);
        int y = (int)MathF.Floor(bounds.Top);
        int width = Math.Max(1, (int)MathF.Ceiling(bounds.Right) - x);
        int height = Math.Max(1, (int)MathF.Ceiling(bounds.Bottom) - y);
        uint flags = 0x0010 | 0x0200; // NOACTIVATE, NOOWNERZORDER
        if (!raise) flags |= 0x0004;
        SetWindowPos(handle, Topmost, x, y, width, height, flags);
    }

    internal static bool TryWindowBounds(nint handle, out Box bounds)
    {
        bool found = GetWindowRect(handle, out var rect);
        bounds = rect.Box;
        return found;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
        public readonly Box Box => new(Left, Top, Right, Bottom);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MONITORINFOEX
    {
        public int Size;
        public NativeRect Monitor, Work;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }

    private delegate bool WindowEnumerator(nint handle, nint data);
    private delegate bool MonitorEnumerator(nint monitor, nint dc, ref NativeRect rect, nint data);

    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(nint context);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorEnumerator callback, nint data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern bool GetMonitorInfoW(nint monitor, ref MONITORINFOEX info);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(nint monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowEnumerator callback, nint data);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint handle);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint handle);
    [DllImport("user32.dll")] private static extern bool IsZoomed(nint handle);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint handle, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetClassNameW(nint handle, StringBuilder name, int length);
    [DllImport("user32.dll", ExactSpelling = true)] private static extern int GetWindowLongW(nint handle, int index);
    [DllImport("user32.dll", ExactSpelling = true)] private static extern int SetWindowLongW(nint handle, int index, int value);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint handle, out NativeRect rectangle);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint handle, int attribute, out NativeRect value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint handle, int attribute, out int value, int size);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInputInfo info);
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetWindowTextW(nint handle, StringBuilder name, int length);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint handle, nint after, int x, int y, int width, int height, uint flags);
}
