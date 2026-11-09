#!/usr/bin/env python3
"""Render Kiln Forever's README screenshots from the addon's own code and the client's own art.

    FOREVER_CORE=/path/to/forever-core python3 tools/screenshots.py

Three scenes, all laid out from the addon's sources and drawn with forever-core's wowmock:

- window.png: the main window (UI/MainFrame.lua, ThreadList.lua, Transcript.lua and Widgets.lua) on
  ButtonFrameTemplate, with a selected Open session so the quick replies show.
- tracker.png: the shared Forever tracker column: the game's Quests section, then the Kiln Forever
  module (uiOrder -5), then a Shortest Path Forever Journey module (uiOrder -3), in section order.
- toast.png: the "Needs you" notice from UI/Toasts.lua, on the client's own scenario toast
  (ScenarioAlertFrameTemplate: Toast-Frame, Toast-IconBG and Toast-Flash) as AlertFrame shows it.

The pinned client build supplies every atlas, texture and font; assets are cached under
~/.cache/wowmock by wowmock itself. The game client is never started or read. Timers and ages are
computed from one fixed `NOW`, so two runs give byte-identical PNGs; `--verify` renders every scene
twice and compares the bytes. The committed PNGs were rendered with Python 3.14.9 and Pillow 13.0.0.
"""

import argparse
import hashlib
import io
import math
import os
import sys
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FOREVER_CORE = Path(os.environ.get("FOREVER_CORE", ROOT.parent / "forever-core")).expanduser()
WOWMOCK = FOREVER_CORE / "tools" / "wowmock"
if not (WOWMOCK / "wowmock.py").is_file():
    sys.exit(f"wowmock.py not found in {WOWMOCK}; set FOREVER_CORE to the forever-core checkout")
sys.path.insert(0, str(WOWMOCK))

from wowmock import (  # noqa: E402
    ARIALN,
    FONTS,
    FRIZQT,
    INSET_FRAME_LAYOUT,
    NORMAL,
    WHITE,
    Font,
    TrackerBlock,
    TrackerModule,
    colored,
    minimal_scrollbar,
    objective_tracker,
    portrait_frame_art,
    rgb,
    scene,
    search_box,
    three_slice_button,
    tiled,
    wrap_text,
)

OUT = ROOT / "docs/screenshots"
MEDIA = ROOT / "addon/KilnForever/media"
BUILD = "1.60.1.70124"  # the pinned UI art build; never the current retail build
SCALE = 2
# One fixed moment, so status ages and live timers do not change between runs.
NOW = 1_794_225_300

# The small font objects the addon names but wowmock's table does not carry.
FONTS.setdefault("Game15Font_Shadow", Font(FRIZQT, 15, WHITE, (1, -1)))
FONTS.setdefault("GameFontGreenSmall", Font(FRIZQT, 10, rgb("1eff00"), (1, -1)))
FONTS.setdefault("GameFontDisable", Font(FRIZQT, 12, (0.5, 0.5, 0.5), (1, -1)))
FONTS.setdefault("ChatFontNormal", Font(ARIALN, 14, WHITE, (1, -1)))
# GameFontWhiteTiny is Friz 9 white; the scenario toast's own heading colours it gold.
FONTS.setdefault("GameFontWhiteTiny", Font(FRIZQT, 9, WHITE))

# ns.COLORS (Core/Init.lua) and the agent tags built from ns.AGENTS.
COLORS = {
    "gold": "ffffd100",
    "white": "ffffffff",
    "grey": "ff9d9d9d",
    "green": "ff1eff00",
    "red": "ffff4040",
    "blue": "ff71d5ff",
    "agent": "ff4a9eff",
    "orange": "ffff9b38",
}
AGENTS = {
    "claude": ("Claude", "orange"),
    "codex": ("Codex", "blue"),
    "opencode": ("OpenCode", "green"),
}
STATUS_TEXT = {"working": "Working", "input": "Needs you", "open": "Open", "done": "Done"}
STATUS_COLOR = {"working": "blue", "input": "orange", "open": "white", "done": "grey"}
DOT_COLORS = {"working": (0.29, 0.62, 1), "input": (1, 0.6, 0.2), "unread": (0.29, 0.62, 1)}


def color(key, text):
    """ns.Color: a |cffRRGGBB escape, as every label in the addon builds them."""
    return f"|c{COLORS.get(key, key)}{text}|r"


def agent_tag(agent):
    """ns.AgentTag: the coloured agent label, or nothing for an unknown agent."""
    entry = AGENTS.get(agent)
    return color(entry[1], entry[0]) if entry else None


def duration(seconds):
    """ns.Duration: 754 -> '12m 34s'."""
    seconds = max(0, math.floor(seconds or 0))
    if seconds < 60:
        return f"{seconds}s"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m {seconds % 60:02d}s"
    hours = minutes // 60
    return f"{hours}h {minutes % 60:02d}m"


def ago(epoch):
    """ns.Ago: 720 -> '12m', 7200 -> '2h'."""
    if not epoch:
        return ""
    delta = max(0, NOW - epoch)
    if delta < 60:
        return "now"
    if delta < 3600:
        return f"{delta // 60}m"
    if delta < 86400:
        return f"{delta // 3600}h"
    return f"{delta // 86400}d"


def clock(epoch):
    """date('%H:%M', at): the sample session clock is UTC, so the bytes do not depend on the host's zone."""
    return time.strftime("%H:%M", time.gmtime(epoch))


# ------------------------------------------------------------------------------------------- sample data
# A plausible afternoon: two agents working, one session waiting on the player, two Open sessions
# (the selected one among them) and two finished. Repositories are the suite's own. No real paths.

PROJECTS = [
    {"id": "/home/dev/src/kiln", "name": "kiln", "act": True},
    {"id": "/home/dev/src/keeper", "name": "keeper", "act": True},
    {"id": "/home/dev/src/shortest-path-forever", "name": "shortest-path-forever", "act": True},
]

THREADS = [
    {
        "id": "claude:host-section",
        "title": "Wire the tracker host",
        "p": "/home/dev/src/kiln",
        "s": "working",
        "l": "npm test",
        "st": NOW - 754,
        "br": "cb/tracker-host",
        "m": "claude",
        "w": "kiln",
        "can": "rxa",
    },
    {
        "id": "codex:bell-cache",
        "title": "Trim the bell cache",
        "p": "/home/dev/src/keeper",
        "s": "working",
        "l": "cargo test",
        "st": NOW - 187,
        "br": "main",
        "m": "codex",
        "w": "kiln",
        "can": "rxa",
    },
    {
        "id": "opencode:install-links",
        "title": "Review the links",
        "p": "/home/dev/src/kiln",
        "s": "input",
        "l": "Remove the data folder on uninstall?",
        "u": NOW - 95,
        "br": "cb/install-links",
        "m": "opencode",
        "w": "kiln",
        "can": "ra",
        "un": True,
    },
    {
        "id": "claude:tracker-host",
        "title": "Check the tracker host",
        "p": "/home/dev/src/shortest-path-forever",
        "s": "open",
        "l": "Open",
        "u": NOW - 720,
        "st": NOW - 4200,
        "br": "cb/tracker-host",
        "m": "claude",
        "w": "kiln",
        "can": "ra",
    },
    {
        "id": "codex:strip-corner",
        "title": "Check the strip corner",
        "p": "/home/dev/src/kiln",
        "s": "open",
        "l": "Open",
        "u": NOW - 5400,
        "st": NOW - 9000,
        "br": "main",
        "m": "codex",
        "w": "kiln",
        "can": "r",
        "un": True,
    },
    {
        "id": "opencode:session-rows",
        "title": "Update the rows",
        "p": "/home/dev/src/keeper",
        "s": "done",
        "l": "Done",
        "u": NOW - 7200,
        "st": NOW - 10800,
        "br": "cb/row-density",
        "m": "opencode",
        "w": "kiln",
        "can": "r",
        "un": True,
        "last": "The rows share one template now.",
    },
    {
        "id": "claude:bell-timer",
        "title": "Drop the old bell timer",
        "p": "/home/dev/src/kiln",
        "s": "done",
        "l": "Done",
        "u": NOW - 172800,
        "st": NOW - 176400,
        "br": "main",
        "m": "claude",
        "w": "kiln",
        "can": "r",
        "last": "Removed; the strip e2e still passes.",
    },
]
SELECTED = "claude:tracker-host"

# The transcript for the selected session (Store.data.view). An Open session's snapshot carries `can = "ra"`:
# kiln reports stop only while a session runs, so the header shows Reply and no Stop.
VIEW = {
    "id": SELECTED,
    "msgs": [
        {"r": "user", "t": "Run the tracker host spec before you touch the layout.", "at": NOW - 3300},
        {
            "r": "assistant",
            "t": "The section stacks under the quests now, and the column reflows on the first frame.",
            "at": NOW - 3200,
        },
        {"r": "tool", "t": "Tool: npm test", "at": NOW - 3100},
        {"r": "tool", "t": "Tool: git diff --stat", "at": NOW - 3000},
    ],
    "abilities": {"reply": None, "stop": False},
}
QUICK_REPLIES = ["Carry on.", "Looks good, thanks.", "Explain that more simply.", "Try a different approach."]


def thread(thread_id):
    return next(t for t in THREADS if t["id"] == thread_id)


def project_name(project_id):
    return next(p["name"] for p in PROJECTS if p["id"] == project_id)


def groups():
    """Store:Groups with the default filter; the order inside each group is the snapshot's order."""
    result = {"working": [], "input": [], "open": [], "done": []}
    for item in THREADS:
        result[{"working": "working", "input": "input", "open": "open", "done": "done"}[item["s"]]].append(item)
    return result


# ------------------------------------------------------------------------------------------ window helpers


def draw_dropdown(canvas, x, y, w, h, text):
    """UI.Cycler (Widgets.lua): the dropdown textholder behind, the arrow at RIGHT (-3, 0), and the
    GameFontHighlightSmall label from LEFT (10, 0) to the arrow's LEFT (-4, 0)."""
    ui = canvas.ui
    canvas.draw(ui.atlas("common-dropdown-textholder"), x, y, w, h)
    art = ui.atlas("common-dropdown-a-button")
    aw = ah = 22
    ax, ay = x + w - 3 - aw, y + (h - ah) / 2
    canvas.draw(art, ax, ay, aw, ah)
    canvas.text(x + 10, y, text, FONTS["GameFontHighlightSmall"], box_height=h, width=ax - 4 - (x + 10))


def draw_search(canvas, x, y, w, h):
    """SearchBoxTemplate at the list's width, with its instructions showing."""
    search_box(canvas, x, y, w, h, "Search")


def draw_side_tab(canvas, x, y, icon):
    """LargeSideTabButtonTemplate as CreateSideTab ends up: 55x55 tab art and the tab's icon at the
    interior extent SetFillToInterior(true, 40) gives it, 40 units cropped 1/32 a side and centred at
    (-3, 0), with the checked tab's overlay."""
    ui = canvas.ui
    back = ui.atlas("common-sidetab")
    cx, cy = x + back.width / 2, y + (back.height - 5) / 2
    canvas.draw(back, cx - back.width / 2, cy - back.height / 2)
    cropped = icon.crop((
        round(icon.width * 0.03125),
        round(icon.height * 0.03125),
        round(icon.width * 0.96875),
        round(icon.height * 0.96875),
    ))
    canvas.draw(cropped, cx - 3 - 20, cy - 20, 40, 40)
    chosen = ui.atlas("common-sidetab-selected")
    canvas.draw(chosen, cx - chosen.width / 2, cy - chosen.height / 2)


def draw_button(canvas, x, y, w, h, text):
    """UI.Button: SharedButtonSmallTemplate, 22 high, its label in GameFontNormal."""
    three_slice_button(canvas, x, y, w, h, text)


def draw_icon_button(canvas, x, y, size, atlas):
    """UI.IconButton: common-button-square-gray-up behind, the atlas fitted inside size-10."""
    ui = canvas.ui
    bg = ui.atlas("common-button-square-gray-up")
    factor = size / max(bg.width, bg.height)
    canvas.draw(bg, x + (size - bg.width * factor) / 2, y + (size - bg.height * factor) / 2,
                bg.width * factor, bg.height * factor)
    art = ui.atlas(atlas)
    factor = (size - 10) / max(art.width, art.height)
    canvas.draw(art, x + (size - art.width * factor) / 2, y + (size - art.height * factor) / 2,
                art.width * factor, art.height * factor)


def draw_thread_row(canvas, x, y, w, item, selected):
    ui = canvas.ui
    height = 46
    if selected:
        sel = ui.atlas("PetList-ButtonSelect")
        canvas.draw(sel, x - 2, y - 2, w + 4, height + 4)
    status = color(STATUS_COLOR[item["s"]], STATUS_TEXT[item["s"]])
    tag = agent_tag(item["m"])
    title = f"{tag}  {item['title']}" if tag else item["title"]
    title_color = (0.75, 0.75, 0.75) if item["s"] == "done" else NORMAL
    assert canvas.text_width(title, FONTS["GameFontNormal"]) <= w - 18 - 74 + 1, f"clipped row title: {title}"
    canvas.text(x + 18, y + 7, title, FONTS["GameFontNormal"], title_color, width=w - 18 - 74)
    canvas.text(x + w - 6, y + 8, status, FONTS["GameFontHighlightSmall"], justify="RIGHT", width=0)
    sub = project_name(item["p"])
    if item.get("br"):
        sub += "  ·  " + item["br"]
    assert canvas.text_width(sub, FONTS["GameFontDisableSmall"]) <= w - 18 - 60 + 1, f"clipped row sub: {sub}"
    canvas.text(x + 18, y + 28, sub, FONTS["GameFontDisableSmall"], width=w - 18 - 60)
    age = duration(NOW - item["st"]) if item["s"] == "working" and item.get("st") else ago(item.get("u"))
    canvas.text(x + w - 6, y + 28, age, FONTS["GameFontDisableSmall"], justify="RIGHT", width=0)
    dot = DOT_COLORS.get(item["s"]) or (DOT_COLORS["unread"] if item.get("un") else None)
    if dot:
        art = ui.atlas("common-roundhighlight")
        canvas.draw(art, x + 6, y + 12, 7, 7, (*dot, 1))


def draw_group_header(canvas, x, y, w, label, count, collapsed):
    ui = canvas.ui
    bg = ui.atlas("common-button-list-collapseExpand")
    canvas.draw(bg, x, y, w, 28)
    mark = ui.atlas("common-button-list-plus" if collapsed else "common-button-list-minus")
    canvas.draw(mark, x + 10, y + (28 - mark.height) / 2)
    text = f"{label}  |cff9d9d9d({count})|r"
    width = canvas.text_width(text, FONTS["Game15Font_Shadow"])
    canvas.text(x + w / 2 + 6 - width / 2, y, text, FONTS["Game15Font_Shadow"], box_height=28, width=width)


def draw_thread_list(canvas, x, y, w, h):
    ui = canvas.ui
    # UI.Dropdown("All repositories") and the SearchBoxTemplate under it.
    draw_dropdown(canvas, x + 8, y + 8, w - 18, 26, "All repositories")
    draw_search(canvas, x + 14, y + 40, w - 26, 20)
    # WowScrollBoxList at TOPLEFT (4, -70) to BOTTOMRIGHT (-18, 4); view padding 2 and spacing 2.
    box_x, box_y, box_w, box_h = x + 4, y + 70, w - 22, h - 74
    bar_x = box_x + box_w + 4
    minimal_scrollbar(canvas, bar_x, box_y, box_h, visible=1.0)  # no thumb: the rows fit
    cursor = box_y + 2
    for key, label in (("working", "Working"), ("input", "Needs you"), ("open", "Open"), ("done", "Done")):
        rows = groups()[key]
        draw_group_header(canvas, box_x + 2, cursor, box_w - 4, label, len(rows), False)
        cursor += 28 + 2
        for item in rows:
            draw_thread_row(canvas, box_x + 2, cursor, box_w - 4, item, item["id"] == SELECTED)
            cursor += 46 + 2


WINDOW_W, WINDOW_H = 940, 640
FRAME_X, FRAME_Y = 16, 20


def draw_message(canvas, x, y, w, msg):
    """InitMessage (Transcript.lua): label at (10, -6), body below it, time at TOPRIGHT (-6, -6)."""
    label = {
        "user": color("gold", "you"),
        "assistant": color("agent", "agent"),
        "system": color("grey", "kiln"),
    }.get(msg["r"], color("grey", "tool"))
    canvas.text(x + 10, y + 6, label, FONTS["GameFontNormalSmall"])
    assert canvas.text_width(msg["t"], FONTS["GameFontHighlight"]) <= w - 20 - 26 + 0.5, "wrapped transcript body"
    canvas.text(x + 10, y + 20, msg["t"], FONTS["GameFontHighlight"], width=w - 20 - 26)
    if msg.get("at"):
        canvas.text(x + w - 6, y + 6, clock(msg["at"]), FONTS["GameFontDisableSmall"], justify="RIGHT", width=0)
    return 46


def draw_option(canvas, x, y, w, label):
    """InitOption: a 26-high row, the 7-unit checkmark bullet at LEFT (16, 0), the label after it."""
    ui = canvas.ui
    canvas.draw(ui.atlas("common-icon-checkmark"), x + 16, y + (26 - 7) / 2, 7, 7, (1, 1, 1, 0.2))
    canvas.text(x + 31, y, label, FONTS["GameFontNormal"], box_height=26, width=w - 31 - 8)


def draw_transcript(canvas, x, y, w, h):
    """The transcript InsetFrameTemplate with its scroll box and rows, clipped to the inset."""
    ui = canvas.ui
    # InsetFrameTemplate Bg: the tiled marble behind the content.
    marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, x, y, w, h, marble.width / ui.scale, marble.height / ui.scale)
    # WowScrollBoxList at TOPLEFT (4, -4) to BOTTOMRIGHT (-20, 4), view padding (4, 8, 0, 0).
    box_x, box_y, box_w, box_h = x + 4, y + 4, w - 24, h - 8
    cursor = box_y + 4
    for msg in VIEW["msgs"]:
        cursor += draw_message(canvas, box_x, cursor, box_w, msg) + 4
    for reply in QUICK_REPLIES:
        draw_option(canvas, box_x, cursor, box_w, reply[:-1] if reply.endswith(".") else reply)
        cursor += 26 + 4
    minimal_scrollbar(canvas, box_x + box_w + 4, box_y, box_h, visible=1.0)  # content fits: no thumb
    canvas.nine_slice(INSET_FRAME_LAYOUT, x, y, w, h)


def draw_header(canvas, x, y, w, h):
    ui = canvas.ui
    bg = ui.atlas("common-button-list-collapseExpand")
    canvas.draw(bg, x, y, w, h)
    item = thread(SELECTED)
    status = color(STATUS_COLOR[item["s"]], STATUS_TEXT[item["s"]])
    label = f"{status}  ·  {project_name(item['p'])}  ·  {ago(item.get('u'))}"
    canvas.text(x + 12, y, label, FONTS["GameFontHighlight"], box_height=h, width=w - 12 - 240,
                justify="CENTER")
    # Stop then Reply, each anchored from the right edge and centred in the 30-high header. The
    # snapshot's `can` flags decide which are shown ('x' stop, 'r' reply).
    can = item.get("can", "")
    if "x" in can:
        draw_button(canvas, x + w - 4 - 80 - 4 - 70, y + 4, 70, 22, "Stop")
    if "r" in can:
        draw_button(canvas, x + w - 4 - 80, y + 4, 80, 22, "Reply")


def window_canvas(ui):
    canvas = ui.canvas(1032, 680)
    x, y = FRAME_X, FRAME_Y
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    tiled(canvas, rock, x + 2, y + 21, WINDOW_W - 4, WINDOW_H - 23, rock.width / ui.scale,
          rock.height / ui.scale)
    streaks = ui.atlas("_UI-Frame-TopTileStreaks")
    canvas.draw(streaks, x + 6, y + 21, WINDOW_W - 8, 43)

    # ButtonFrameTemplate's Inset at TOPLEFT (4, -60) to BOTTOMRIGHT (-6, 26).
    ix, iy, iw, ih = x + 4, y + 60, WINDOW_W - 10, WINDOW_H - 86
    marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, ix, iy, iw, ih, marble.width / ui.scale, marble.height / ui.scale)

    # Pages.threads: Left 300 wide, a 4-unit divider gap, then Right.
    left_x, left_y, left_w = ix, iy, 300
    right_x = left_x + left_w + 4
    right_w = ix + iw - right_x
    item = thread(SELECTED)
    draw_thread_list(canvas, left_x, left_y, left_w, ih)
    header_x, header_y, header_w, header_h = right_x + 4, iy + 4, right_w - 8, 30
    draw_header(canvas, header_x, header_y, header_w, header_h)
    transcript_x = right_x + 2
    transcript_y = header_y + header_h + 4
    transcript_w = right_w - 4
    composer_top = iy + ih - 2 - 92
    transcript_h = (composer_top - 4) - transcript_y
    draw_transcript(canvas, transcript_x, transcript_y, transcript_w, transcript_h)

    # Composer: UI.Inset 92 high at BOTTOMLEFT (2, 2) to BOTTOMRIGHT (-2, 2).
    cx, cy, cw, ch = right_x + 2, iy + ih - 2 - 92, right_w - 4, 92
    tiled(canvas, marble, cx, cy, cw, ch, marble.width / ui.scale, marble.height / ui.scale)
    placeholder = "Queue a follow-up" if item["s"] == "working" else "Message the agent"
    canvas.text(cx + 8, cy + 6, placeholder + "  (Shift+Enter for a new line)", FONTS["GameFontDisable"])
    canvas.text(cx + cw - 8, cy + ch - 5 - 10, "2000", FONTS["GameFontDisableSmall"], justify="RIGHT", width=0)
    canvas.nine_slice(INSET_FRAME_LAYOUT, cx, cy, cw, ch)

    canvas.nine_slice(INSET_FRAME_LAYOUT, ix, iy, iw, ih)

    # Bottom button bar, anchored to the frame.
    draw_button(canvas, x + 6, y + WINDOW_H - 4 - 22, 110, 22, "Refresh")
    draw_button(canvas, x + 176, y + WINDOW_H - 4 - 22, 130, 22, "New Session")
    draw_button(canvas, x + 318, y + WINDOW_H - 4 - 22, 110, 22, "Back")
    draw_button(canvas, x + WINDOW_W - 6 - 110, y + WINDOW_H - 4 - 22, 110, 22, "Send")

    # The window's one LargeSideTabButtonTemplate, checked on the threads page.
    icon = Image.open(MEDIA / "icon-400.png").convert("RGBA")
    draw_side_tab(canvas, x + WINDOW_W, y + 36, icon)

    # Subtitle: the selected session's title, then the link status under it (MainFrame.lua's
    # f.Subtitle at TOP (20, -30) and f.Status at its BOTTOM (0, -2)).
    canvas.text(x + WINDOW_W / 2 + 20 - (WINDOW_W - 220) / 2, y + 30, item["title"],
                FONTS["GameFontNormalLarge"], justify="CENTER", width=WINDOW_W - 220)
    canvas.text(x + WINDOW_W / 2 - (WINDOW_W - 220) / 2, y + 48, color("green", "Connected"),
                FONTS["GameFontGreenSmall"], justify="CENTER", width=WINDOW_W - 220)

    # Collapse the thread list: UI.IconButton at TOPRIGHT (-10, -32), the back arrow facing left
    # while the list is shown.
    draw_icon_button(canvas, x + WINDOW_W - 10 - 24, y + 32, 24, "common-dropdown-icon-back")

    # PortraitFrameTemplate: the masked portrait, the metal frame, the title and the close button.
    portrait_frame_art(canvas, x, y, WINDOW_W, WINDOW_H, icon, "Kiln Forever")
    return canvas


# ------------------------------------------------------------------------------------------ tracker scene


def tracker_canvas(ui):
    gold = ui.global_color("OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR")[:3]
    # Quests: two real Northshire (Alliance) quests with their own tracker lines.
    quests = TrackerModule(
        "Quests",
        [
            TrackerBlock("Kobold Camp Cleanup", [("Kobold Vermin slain: 0/10", True)]),
            TrackerBlock("Wolves Across the Border", [("Tough Wolf Meat: 0/8", True)]),
        ],
    )
    # UI/Tracker.lua: Needs you first, then working with live timers, then unread finished ones, at
    # most six. Block headers are the session titles; the line is StatusText with the tracker colours.
    def tracker_status(item):
        if item["s"] == "working":
            return f"{item['l']}  {duration(NOW - item['st'])}"
        if item["s"] == "input":
            return color("white", item["l"])
        if item["s"] == "done":
            return color("ff999999", "Done  " + ago(item["u"]))
        return "Open  " + ago(item["u"])

    def session_block(item):
        # The client colours the whole objective line, dash included, from AddObjective's colour.
        dash = True
        if item["s"] == "input":
            dash = color("white", "- ")
        elif item["s"] == "done":
            dash = color("ff999999", "- ")
        return TrackerBlock(item["title"], [(tracker_status(item), dash)])

    kiln = TrackerModule(
        "Kiln Forever",
        [
            session_block(thread("opencode:install-links")),
            session_block(thread("claude:host-section")),
            session_block(thread("codex:bell-cache")),
            session_block(thread("codex:strip-corner")),
            session_block(thread("opencode:session-rows")),
        ],
    )
    # Shortest Path Forever's Journey module, as its scene draws it: the countdown in the module
    # header, the goal pin and destination in the block header, and one marked row per leg.
    def mark(atlas):
        art = ui.atlas(atlas)
        width = max(1, math.floor(12 * art.width / art.height + 0.5))
        return f"|A:{atlas}:12:{width}|a"

    def row(atlas, verb, place, detail):
        return (
            f"{verb} {colored(place, gold)}   {colored(detail, rgb('808080'))}",
            f"{mark(atlas)} ",
        )

    journey = TrackerModule(
        "Journey  44:47 · 9.2k yd",
        [
            TrackerBlock(
                "|A:Waypoint-MapPin-Tracked:12:12|a Journey to " + colored("Menethil Harbor", gold),
                [
                    row("poi-traveldirections-arrow", "Walk to", "Auberdine northeast pier", "1:20"),
                    row("flightmasterferry", "Boat to", "Wetlands", "leaves in 2:28 · 1:20"),
                    row("poi-traveldirections-arrow", "Walk to", "Menethil Harbor", "4:12"),
                ],
            )
        ],
    )
    # The host sorts by uiOrder and stacks with a 10-unit gap; -5 is above -3, below the quests.
    canvas, _ = objective_tracker(ui, [quests, kiln, journey], container=True)
    assert [m.header for m in (quests, kiln, journey)] == ["Quests", "Kiln Forever", "Journey  44:47 · 9.2k yd"]
    return canvas


# -------------------------------------------------------------------------------------------- toast scene

# ScenarioAlertFrameTemplate (Blizzard_FrameXML/Mainline/AlertFrameSystems.xml): 311x78, Toast-Frame across the
# whole frame, Toast-IconBG 47x52 at LEFT (15, 0), the icon 45 square at LEFT (17, 0), the unnamed heading at
# TOP (20, -22) in a 200x12 box, and the session name at TOP (20, -46), 200 wide.
TOAST_W, TOAST_H = 311, 78
TOAST_ICON = 45
TOAST_TEXT_X = TOAST_W / 2 + 20 - 100
TOAST_TEXT_W = 200


def toast_canvas(ui):
    """Toasts:SetUp for an input session: the status and repository on the small gold line, the session
    title on the name line. An input session's snapshot carries no `last` line."""
    canvas = ui.canvas(TOAST_W, TOAST_H)
    canvas.draw(ui.atlas("Toast-Frame"), 0, 0, TOAST_W, TOAST_H)
    backing = ui.atlas("Toast-IconBG")
    canvas.draw(backing, 15, (TOAST_H - backing.height) / 2)
    icon = Image.open(MEDIA / "icon-400.png").convert("RGBA")
    canvas.draw(icon, 17, (TOAST_H - TOAST_ICON) / 2, TOAST_ICON, TOAST_ICON)
    item = thread("opencode:install-links")
    heading = color("orange", "Needs you") + color("grey", "  ·  " + project_name(item["p"]))
    font = FONTS["GameFontWhiteTiny"]
    assert canvas.text_width(heading, font) <= TOAST_TEXT_W, "clipped toast heading"
    # Both FontStrings are CENTER justified (the XML leaves justifyH at its default) inside their 200-wide
    # boxes, whose centre sits 20 units right of the frame centre.
    canvas.text(TOAST_TEXT_X, 22, heading, font, box_height=12, width=TOAST_TEXT_W, justify="CENTER")
    lines = wrap_text(canvas, item["title"], FONTS["GameFontHighlight"], TOAST_TEXT_W, 2)
    for index, line in enumerate(lines):
        canvas.text(TOAST_TEXT_X, 46 + index * 12, line, FONTS["GameFontHighlight"], width=TOAST_TEXT_W,
                    justify="CENTER")
    return canvas


# ------------------------------------------------------------------------------------------------ output

SCENES = {
    "window": window_canvas,
    "tracker": tracker_canvas,
    "toast": toast_canvas,
}


def encode(name, ui):
    buffer = io.BytesIO()
    scene(ui, [(SCENES[name](ui), 0, 0)]).image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="render twice and require identical bytes")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    failed = []
    for name in SCENES:
        try:
            from wowmock import Ui

            content = encode(name, Ui(build=BUILD, scale=SCALE, atlas_set=1))
            if args.verify:
                assert content == encode(name, Ui(build=BUILD, scale=SCALE, atlas_set=1)), f"{name}: nondeterministic bytes"
            path = OUT / f"{name}.png"
            path.write_bytes(content)
            print(f"{path.relative_to(ROOT)}  {len(content):,} bytes  sha256:{hashlib.sha256(content).hexdigest()}")
        except Exception as error:  # noqa: BLE001 - report the scene and keep going
            failed.append(name)
            print(f"{name}: {type(error).__name__}: {error}", file=sys.stderr)
    if failed:
        sys.exit("Not rendered: " + ", ".join(failed))


if __name__ == "__main__":
    main()
