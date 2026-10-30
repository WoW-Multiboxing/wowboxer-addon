#!/usr/bin/env python3
"""Read-only capture of a World of Warcraft window (Windows only): find the client's window by its exe path and copy
its pixels with PrintWindow (PW_RENDERFULLCONTENT). Never sends input, never focuses or moves the window.

  from wowgrab import find_window, grab
  hwnd = find_window("_classic_era_")   # or "_forever_"
  img = grab(hwnd)                      # PIL.Image (RGB) of the client area, or None
"""
import ctypes
import ctypes.wintypes as wt

user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

PW_CLIENTONLY, PW_RENDERFULLCONTENT = 1, 2
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def _exe_of(hwnd):
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    h = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if not h:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wt.DWORD(1024)
        if kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return buf.value
        return ""
    finally:
        kernel32.CloseHandle(h)


def windows(client=None):
    """[(hwnd, exe path, title)] of visible WoW client windows (exe under the given client folder, if any)."""
    out = []
    EnumProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)

    def cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, title, n + 1)
        if title.value != "World of Warcraft":
            return True
        exe = _exe_of(hwnd)
        if exe.lower().endswith((".exe",)) and (client is None or ("\\" + client + "\\").lower() in exe.lower()):
            out.append((hwnd, exe, title.value))
        return True

    user32.EnumWindows(EnumProc(cb), 0)
    return out


def find_window(client):
    ws = windows(client)
    return ws[0][0] if ws else None


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG), ("biPlanes", wt.WORD),
                ("biBitCount", wt.WORD), ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
                ("biXPelsPerMeter", wt.LONG), ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD), ("biClrImportant", wt.DWORD)]


def grab(hwnd):
    """The client area of the window as a PIL RGB image (PrintWindow; works for a covered window), or None."""
    from PIL import Image
    rect = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    w, h = rect.right - rect.left, rect.bottom - rect.top
    if w <= 0 or h <= 0:
        return None
    hdc_win = user32.GetDC(hwnd)
    hdc = gdi32.CreateCompatibleDC(hdc_win)
    bmp = gdi32.CreateCompatibleBitmap(hdc_win, w, h)
    old = gdi32.SelectObject(hdc, bmp)
    try:
        ok = user32.PrintWindow(hwnd, hdc, PW_CLIENTONLY | PW_RENDERFULLCONTENT)
        if not ok:
            return None
        bi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
        buf = ctypes.create_string_buffer(w * h * 4)
        gdi32.GetDIBits(hdc, bmp, 0, h, buf, ctypes.byref(bi), 0)
        return Image.frombuffer("RGB", (w, h), buf, "raw", "BGRX", 0, 1).copy()
    finally:
        gdi32.SelectObject(hdc, old)
        gdi32.DeleteObject(bmp)
        gdi32.DeleteDC(hdc)
        user32.ReleaseDC(hwnd, hdc_win)


if __name__ == "__main__":
    import sys
    for hwnd, exe, _ in windows():
        print(hwnd, exe)
    if len(sys.argv) > 2:
        img = grab(find_window(sys.argv[1]))
        print("grabbed", img and img.size)
        if img:
            img.save(sys.argv[2])
