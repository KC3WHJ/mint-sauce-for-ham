#!/usr/bin/env python3
"""10-minute station ID reminder. Start once; it beeps + flashes every
10 minutes and auto-restarts the countdown until Cancel is clicked."""
import re
import subprocess
import tkinter as tk

INTERVAL_SECONDS = 10 * 60
BEEP_SOUND = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
BG_NORMAL = "#1a1c23"
FG_NORMAL = "#e6e6e6"
BG_ALERT = "#c0392b"
TITLEBAR_BLUE = "#6fa8dc"
WINDOW_WIDTH = 130
WINDOW_HEIGHT = 62

remaining = INTERVAL_SECONDS
running = False
tick_job = None
flash_job = None
flash_count = 0


def format_time(secs):
    return f"{secs // 60:02d}:{secs % 60:02d}"


def play_beep():
    subprocess.Popen(
        ["paplay", BEEP_SOUND],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def flash_step():
    global flash_job, flash_count
    flash_count += 1
    root.configure(bg=BG_ALERT if flash_count % 2 else BG_NORMAL)
    label.configure(bg=BG_ALERT if flash_count % 2 else BG_NORMAL)
    if flash_count < 8:
        flash_job = root.after(250, flash_step)
    else:
        root.configure(bg=BG_NORMAL)
        label.configure(bg=BG_NORMAL)
        flash_count = 0
        start_countdown()


def alert():
    global remaining
    play_beep()
    label.configure(text="ID NOW", fg=BG_ALERT)
    flash_step()


def tick():
    global remaining, tick_job
    if not running:
        return
    remaining -= 1
    if remaining <= 0:
        label.configure(text="ID NOW")
        alert()
        return
    label.configure(text=format_time(remaining), fg=FG_NORMAL)
    tick_job = root.after(1000, tick)


def start_countdown():
    global remaining, tick_job
    remaining = INTERVAL_SECONDS
    label.configure(text=format_time(remaining), fg=FG_NORMAL)
    tick_job = root.after(1000, tick)


def on_start():
    global running
    if running:
        return
    running = True
    start_btn.configure(state=tk.DISABLED)
    cancel_btn.configure(state=tk.NORMAL)
    start_countdown()


def on_cancel():
    global running, remaining, tick_job, flash_job, flash_count
    running = False
    if tick_job:
        root.after_cancel(tick_job)
        tick_job = None
    if flash_job:
        root.after_cancel(flash_job)
        flash_job = None
    flash_count = 0
    remaining = INTERVAL_SECONDS
    root.configure(bg=BG_NORMAL)
    label.configure(text=format_time(remaining), bg=BG_NORMAL, fg=FG_NORMAL)
    start_btn.configure(state=tk.NORMAL)
    cancel_btn.configure(state=tk.DISABLED)


root = tk.Tk()
root.title("ID Timer")
root.configure(bg=BG_NORMAL)
root.resizable(False, False)
# "-type desktop" (a prior approach, matching Conky's own own_window_type)
# was tried so this sits above the wallpaper but below normal app windows -
# but that defeats the point of a station-ID reminder: it silently vanishes
# behind whatever you're actually using, right when you need to notice it.
# overrideredirect(True) takes the window out of window-manager management
# entirely, which (combined with -topmost) keeps it reliably on top of every
# other window under Marco/MATE - confirmed 2026-09-10. It also means this
# window won't appear in taskbars/alt-tab/wmctrl -l, which is fine for a
# small persistent utility never meant to be switched to directly. Manual
# drag handling below still works fine, since it's pure Tkinter mouse-event
# binding, independent of any window-manager-assisted move/decoration.
root.overrideredirect(True)
root.wm_attributes("-topmost", True)


def find_window_geometry(name_substring):
    """(x, y, width, height) of the first window whose wmctrl title
    contains name_substring, or None if not found. wmctrl only to find the
    window id, then xwininfo for its actual geometry - wmctrl -G's own x/y
    columns are unreliable on this machine (confirmed separately).
    """
    try:
        out = subprocess.run(
            ["wmctrl", "-l"], capture_output=True, text=True, timeout=2,
        ).stdout
        win_id = next(
            (parts[0] for line in out.splitlines()
             if len(parts := line.split(None, 3)) == 4
             and name_substring in parts[3].lower()),
            None,
        )
        if not win_id:
            return None
        info = subprocess.run(
            ["xwininfo", "-id", win_id],
            capture_output=True, text=True, timeout=2,
        ).stdout
        x = int(re.search(r"Absolute upper-left X:\s+(-?\d+)", info).group(1))
        y = int(re.search(r"Absolute upper-left Y:\s+(-?\d+)", info).group(1))
        w = int(re.search(r"Width:\s+(\d+)", info).group(1))
        h = int(re.search(r"Height:\s+(\d+)", info).group(1))
        return x, y, w, h
    except Exception:
        return None


# Docked just above the taskbar clock (bottom-right) rather than below Conky
# - small and out of the way, but still guaranteed visible since it's
# -topmost. Queries the actual live panel window rather than hardcoding
# screen height, same reasoning as the old Conky-relative positioning this
# replaced: assumed constants drift from reality across machines/panel
# configurations. RIGHT_MARGIN approximates the clock applet's own width
# within the panel, since individual panel applets aren't separate
# top-level windows and can't be queried directly.
RIGHT_MARGIN = 10
GAP_ABOVE = 6
screen_w = root.winfo_screenwidth()
screen_h = root.winfo_screenheight()
panel_geom = find_window_geometry("panel")
if panel_geom:
    px, py, pw, ph = panel_geom
    pos_x = px + pw - WINDOW_WIDTH - RIGHT_MARGIN
    pos_y = py - WINDOW_HEIGHT - GAP_ABOVE
else:
    pos_x = screen_w - WINDOW_WIDTH - RIGHT_MARGIN
    pos_y = screen_h - WINDOW_HEIGHT - 34  # ~typical panel height as a guess
root.geometry(f"{WINDOW_WIDTH}x{WINDOW_HEIGHT}+{pos_x}+{pos_y}")

titlebar = tk.Frame(root, bg=TITLEBAR_BLUE, height=14)
titlebar.pack(fill=tk.X, side=tk.TOP)
titlebar_label = tk.Label(
    titlebar, text="ID Timer", bg=TITLEBAR_BLUE, fg="#1a1c23",
    font=("DejaVu Sans", 7, "bold"),
)
titlebar_label.pack(pady=0)


def start_move(event):
    root._drag_x = event.x
    root._drag_y = event.y


def do_move(event):
    x = root.winfo_pointerx() - root._drag_x
    y = root.winfo_pointery() - root._drag_y
    root.geometry(f"+{x}+{y}")


titlebar.bind("<Button-1>", start_move)
titlebar.bind("<B1-Motion>", do_move)
titlebar_label.bind("<Button-1>", start_move)
titlebar_label.bind("<B1-Motion>", do_move)

label = tk.Label(
    root, text=format_time(INTERVAL_SECONDS),
    font=("DejaVu Sans Mono", 14, "bold"),
    bg=BG_NORMAL, fg=FG_NORMAL, pady=1,
)
label.pack()

btn_frame = tk.Frame(root, bg=BG_NORMAL)
btn_frame.pack(pady=(0, 3))

start_btn = tk.Button(
    btn_frame, text="Start", width=5, font=("DejaVu Sans", 7),
    command=on_start,
)
start_btn.pack(side=tk.LEFT, padx=3)

cancel_btn = tk.Button(
    btn_frame, text="Cancel", width=5, font=("DejaVu Sans", 7),
    command=on_cancel, state=tk.DISABLED,
)
cancel_btn.pack(side=tk.LEFT, padx=3)


def keep_on_top():
    """overrideredirect windows aren't managed by the window manager, so
    -topmost only takes effect once at creation - it does NOT defend
    against falling behind later as other windows get raised (confirmed
    2026-09-10: after a normal session of opening flrig/VarAC/WSJT-X/etc.,
    this window was still being *drawn* on top but had silently fallen
    behind the desktop icon layer in the real X11 input-stacking order, so
    it looked fine but Start/Cancel clicks landed on the desktop instead
    of the buttons - completely invisible unless you specifically check
    window stacking, not just what's rendered on screen). root.lift()
    re-raises it; cheap enough to just do on every tick.
    """
    root.lift()
    root.after(3000, keep_on_top)


keep_on_top()
root.mainloop()
