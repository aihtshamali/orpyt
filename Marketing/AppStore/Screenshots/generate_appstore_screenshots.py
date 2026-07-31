from __future__ import annotations

from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Marketing" / "AppStore" / "Screenshots" / "Generated" / "AppStore-2880x1800"
ICON = ROOT / "Assets" / "Assets.xcassets" / "AppIcon.appiconset" / "1024.png"

W, H = 2880, 1800


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    paths = {
        "regular": "/System/Library/Fonts/SFNS.ttf",
        "medium": "/System/Library/Fonts/SFNS.ttf",
        "bold": "/System/Library/Fonts/SFNS.ttf",
        "mono": "/System/Library/Fonts/SFNSMono.ttf",
    }
    return ImageFont.truetype(paths.get(weight, paths["regular"]), size=size)


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return (
        int(hex_color[0:2], 16),
        int(hex_color[2:4], 16),
        int(hex_color[4:6], 16),
        alpha,
    )


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    max_width: int,
    fnt: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    line_gap: int = 12,
) -> int:
    x, y = xy
    lines: list[str] = []
    for para in text.split("\n"):
        words = para.split(" ")
        line = ""
        for word in words:
            test = word if not line else f"{line} {word}"
            if draw.textbbox((0, 0), test, font=fnt)[2] <= max_width:
                line = test
            else:
                if line:
                    lines.append(line)
                line = word
        if line:
            lines.append(line)
    for line in lines:
        draw.text((x, y), line, font=fnt, fill=fill)
        y += text_size(draw, line, fnt)[1] + line_gap
    return y


def add_shadow(
    base: Image.Image,
    mask: Image.Image,
    offset: tuple[int, int],
    blur: int,
    color: tuple[int, int, int, int],
) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", base.size, color)
    shifted = Image.new("L", base.size, 0)
    shifted.paste(mask, offset)
    shadow_layer.putalpha(shifted.filter(ImageFilter.GaussianBlur(blur)))
    shadow.alpha_composite(shadow_layer)
    base.alpha_composite(shadow)


def rounded_panel(
    base: Image.Image,
    box: tuple[int, int, int, int],
    radius: int,
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int] | None = None,
    width: int = 2,
    shadow: bool = True,
) -> None:
    x1, y1, x2, y2 = box
    mask = Image.new("L", base.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(box, radius=radius, fill=255)
    if shadow:
        add_shadow(base, mask.crop(box), (x1 + 14, y1 + 22), 28, (0, 0, 0, 58))
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    base.alpha_composite(layer)


def background(theme: str = "dark") -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    px = img.load()
    if theme == "light":
        top = (241, 248, 255)
        bottom = (225, 232, 249)
    else:
        top = (6, 12, 29)
        bottom = (15, 25, 55)
    for y in range(H):
        t = y / H
        for x in range(W):
            glow = max(0, 1 - math.hypot((x - W * 0.72) / 1350, (y - H * 0.55) / 900))
            blue = int(32 * glow)
            r = int(top[0] * (1 - t) + bottom[0] * t)
            g = int(top[1] * (1 - t) + bottom[1] * t)
            b = int(top[2] * (1 - t) + bottom[2] * t) + blue
            px[x, y] = (min(r, 255), min(g, 255), min(b, 255), 255)

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if theme == "dark":
        random.seed(42)
        for _ in range(280):
            x = random.randint(0, W)
            y = random.randint(0, H)
            a = random.randint(35, 155)
            d.ellipse((x, y, x + 2, y + 2), fill=(200, 220, 255, a))
        d.arc((1120, 470, 3850, 3000), 205, 325, fill=(65, 168, 255, 155), width=7)
        d.arc((1135, 488, 3830, 2990), 207, 326, fill=(155, 205, 255, 75), width=18)
        d.ellipse((1500, 1140, 3780, 2660), fill=(0, 65, 160, 18), outline=(80, 160, 255, 44), width=5)
    else:
        d.ellipse((-420, -350, 1240, 1050), fill=(118, 190, 255, 32))
        d.ellipse((1680, 140, 3420, 1710), fill=(122, 88, 255, 22))
        d.arc((1320, 500, 3800, 2900), 205, 325, fill=(70, 150, 255, 95), width=8)
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(1)))


def mac_menu_bar(base: Image.Image, pill: str = "LON 9:35 AM | NYC 4:35 AM", alert: str | None = None) -> None:
    d = ImageDraw.Draw(base)
    d.rectangle((0, 0, W, 86), fill=(2, 5, 12, 222))
    d.text((58, 31), "Orpyt", font=font(24, "bold"), fill=(245, 248, 255, 220))
    pill_x, pill_y = 980, 18
    if alert:
        w, _ = text_size(d, alert, font(20, "bold"))
        rounded_panel(base, (pill_x - w // 2 - 35, pill_y, pill_x + w // 2 + 35, pill_y + 48), 24, rgba("#ff5565", 245), shadow=False)
        d.text((pill_x - w // 2, pill_y + 12), alert, font=font(20, "bold"), fill=(255, 255, 255, 255))
        pill_x += 155
    tw, _ = text_size(d, pill, font(23, "bold"))
    rounded_panel(base, (pill_x, pill_y, pill_x + tw + 60, pill_y + 48), 15, rgba("#17243a", 245), rgba("#4f84ff", 130), 2, False)
    d.text((pill_x + 30, pill_y + 12), pill, font=font(23, "bold"), fill=(242, 248, 255, 250))
    x = W - 500
    for i in range(3):
        d.ellipse((x + i * 34, 39, x + i * 34 + 8, 47), fill=(230, 238, 255, 145))
    d.text((W - 330, 29), "Sat 23 May  9:35 AM", font=font(23, "regular"), fill=(230, 238, 255, 170))


def app_icon(size: int) -> Image.Image:
    icon = Image.open(ICON).convert("RGBA").resize((int(size * 0.78), int(size * 0.78)), Image.Resampling.LANCZOS)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=int(size * 0.22), fill=255)
    bg = Image.new("RGBA", (size, size), (248, 250, 255, 255))
    bg.putalpha(mask)
    img.alpha_composite(bg)
    img.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
    return img


def draw_action_icon(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], kind: str, color: tuple[int, int, int, int]) -> None:
    x1, y1, x2, y2 = box
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    if kind == "search":
        draw.ellipse((cx - 13, cy - 15, cx + 9, cy + 7), outline=color, width=4)
        draw.line((cx + 6, cy + 6, cx + 18, cy + 18), fill=color, width=4)
    elif kind == "swap":
        draw.line((cx - 16, cy - 10, cx + 14, cy - 10), fill=color, width=4)
        draw.polygon([(cx + 14, cy - 18), (cx + 25, cy - 10), (cx + 14, cy - 2)], fill=color)
        draw.line((cx + 16, cy + 11, cx - 14, cy + 11), fill=color, width=4)
        draw.polygon([(cx - 14, cy + 3), (cx - 25, cy + 11), (cx - 14, cy + 19)], fill=color)
    elif kind == "sliders":
        for yy, knob in [(cy - 15, cx - 8), (cy, cx + 10), (cy + 15, cx - 2)]:
            draw.line((cx - 21, yy, cx + 21, yy), fill=color, width=3)
            draw.ellipse((knob - 5, yy - 5, knob + 5, yy + 5), fill=color)
    elif kind == "power":
        draw.arc((cx - 16, cy - 14, cx + 16, cy + 18), 35, 325, fill=color, width=4)
        draw.line((cx, cy - 20, cx, cy + 1), fill=color, width=4)


def header_copy(
    base: Image.Image,
    eyebrow: str,
    headline: str,
    body: str,
    x: int,
    y: int,
    width: int,
    dark: bool = True,
) -> None:
    d = ImageDraw.Draw(base)
    accent = rgba("#61b8ff" if dark else "#007aff", 255)
    primary = rgba("#f8fbff" if dark else "#101827", 255)
    secondary = rgba("#b6c5df" if dark else "#536070", 255)
    d.text((x, y), eyebrow.upper(), font=font(22, "bold"), fill=accent)
    y += 54
    for i, line in enumerate(headline.split("\n")):
        color = primary if i == 0 else rgba("#bde1ff" if dark else "#006bdc", 255)
        d.text((x, y), line, font=font(92, "bold"), fill=color)
        y += 102
    y += 24
    draw_wrapped(d, body, (x, y), width, font(35), secondary, line_gap=17)


def feature_pills(base: Image.Image, items: list[tuple[str, str]], x: int, y: int, dark: bool = True) -> None:
    d = ImageDraw.Draw(base)
    for icon, label in items:
        rounded_panel(base, (x, y, x + 310, y + 112), 32, rgba("#0f2037", 190) if dark else rgba("#ffffff", 190), rgba("#7ebdff", 45), 2, True)
        d.text((x + 28, y + 30), icon, font=font(34, "bold"), fill=rgba("#5db9ff", 255))
        icon_w, _ = text_size(d, icon, font(34, "bold"))
        d.text((x + 48 + icon_w, y + 28), label, font=font(25, "bold"), fill=rgba("#edf6ff" if dark else "#142033", 245))
        x += 350


def cloud_icon(d: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    d.ellipse((x + 11, y + 12, x + 49, y + 48), fill=color)
    d.ellipse((x + 39, y + 2, x + 86, y + 49), fill=color)
    d.rounded_rectangle((x, y + 30, x + 98, y + 58), 18, fill=color)


def small_cloud(d: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    d.ellipse((x + 5, y + 9, x + 27, y + 31), fill=color)
    d.ellipse((x + 22, y + 2, x + 51, y + 31), fill=color)
    d.rounded_rectangle((x, y + 20, x + 58, y + 38), 10, fill=color)


def weather_sun(d: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    d.ellipse((x + 23, y + 23, x + 70, y + 70), fill=color)
    for angle in range(0, 360, 45):
        cx, cy = x + 46, y + 46
        dx = math.cos(math.radians(angle))
        dy = math.sin(math.radians(angle))
        d.line((cx + dx * 35, cy + dy * 35, cx + dx * 52, cy + dy * 52), fill=color, width=6)


def clock_card(
    base: Image.Image,
    box: tuple[int, int, int, int],
    city: str,
    role: str,
    time_text: str,
    date: str,
    tz: str,
    weather: str,
    location: str,
    accent: str,
    dark: bool = False,
) -> None:
    d = ImageDraw.Draw(base)
    fill = rgba("#f4f9ff", 242) if not dark else rgba("#27354d", 245)
    line = rgba("#ffffff", 75) if not dark else rgba("#a9c7ff", 52)
    rounded_panel(base, box, 42, fill, line, 2, True)
    x1, y1, x2, y2 = box
    ac = rgba(accent, 255)
    d.ellipse((x1 + 56, y1 + 64, x1 + 76, y1 + 84), fill=ac)
    small_cloud(d, x1 + 94, y1 + 58, ac)
    d.text((x1 + 182, y1 + 59), city, font=font(30, "bold"), fill=rgba("#2a3342" if not dark else "#ecf4ff", 245))
    d.text((x2 - 185, y1 + 59), role, font=font(24, "bold"), fill=rgba("#667386" if not dark else "#b6c2d3", 245))
    d.text((x1 + 62, y1 + 155), time_text, font=font(114), fill=rgba("#252d39" if not dark else "#f2f7ff", 250))
    d.text((x1 + 62, y1 + 305), date, font=font(38), fill=rgba("#697585" if not dark else "#cad5e6", 245))
    rounded_panel(base, (x1 + 62, y1 + 405, x1 + 185, y1 + 465), 30, rgba("#ffffff", 160) if not dark else rgba("#ffffff", 24), shadow=False)
    d.text((x1 + 86, y1 + 421), tz, font=font(24, "bold"), fill=rgba("#6b7584" if not dark else "#d3dbea", 245))
    cloud_icon(d, x1 + 64, y2 - 155, ac)
    d.text((x1 + 145, y2 - 140), weather, font=font(26, "bold"), fill=rgba("#2f3744" if not dark else "#f0f4ff", 245))
    d.text((x1 + 145, y2 - 101), location, font=font(22), fill=rgba("#697486" if not dark else "#bdc8d9", 245))


def popover(base: Image.Image, box: tuple[int, int, int, int], dark: bool = False, expanded: bool = True, footer: bool = True) -> None:
    d = ImageDraw.Draw(base)
    x1, y1, x2, y2 = box
    fill = rgba("#f5faff", 246) if not dark else rgba("#1d2a44", 246)
    outline = rgba("#8ac0ff", 105) if not dark else rgba("#80afff", 70)
    rounded_panel(base, box, 64, fill, outline, 3, True)
    d.text((x1 + 64, y1 + 62), "Orpyt", font=font(42, "bold"), fill=rgba("#27313f" if not dark else "#f5f8ff", 255))
    d.text((x1 + 64, y1 + 112), "Synced across cities, weather, and work.", font=font(25), fill=rgba("#5b6574" if not dark else "#aebbd1", 245))
    actions = ["search", "swap", "sliders", "power"]
    ax = x2 - 340
    for item in actions:
        rounded_panel(base, (ax, y1 + 54, ax + 62, y1 + 116), 22, rgba("#ffffff", 120) if not dark else rgba("#ffffff", 32), shadow=False)
        draw_action_icon(d, (ax + 10, y1 + 64, ax + 52, y1 + 106), item, rgba("#35404f" if not dark else "#eaf1fb", 245))
        ax += 78
    card_y = y1 + 190
    card_w = (x2 - x1 - 156) // 2
    clock_card(base, (x1 + 64, card_y, x1 + 64 + card_w, card_y + 560), "LON", "Primary", "9:35 AM", "Sat, 23 May", "GMT+1", "16°C • Clear", "London • Feels like 17°C", "#9b6cff", dark)
    clock_card(base, (x1 + 92 + card_w, card_y, x2 - 64, card_y + 560), "NYC", "Secondary", "4:35 AM", "Sat, 23 May", "GMT-4", "11°C • Overcast", "New York • Feels like 9°C", "#3ba6ff", dark)
    meet_y = card_y + 625
    meeting_card(base, (x1 + 64, meet_y, x2 - 64, meet_y + (420 if expanded else 230)), dark, expanded)
    if not footer:
        return
    tiles_y = meet_y + (460 if expanded else 270)
    tile_w = (x2 - x1 - 156) // 2
    stat_tile(base, (x1 + 64, tiles_y, x1 + 64 + tile_w, tiles_y + 134), "12h", "Clock mode", dark)
    stat_tile(base, (x1 + 92 + tile_w, tiles_y, x2 - 64, tiles_y + 134), "Seconds Off", "Precision", dark)
    scroller(base, (x1 + 64, tiles_y + 175, x2 - 64, y2 - 80), dark)


def stat_tile(base: Image.Image, box: tuple[int, int, int, int], title: str, label: str, dark: bool) -> None:
    d = ImageDraw.Draw(base)
    rounded_panel(base, box, 28, rgba("#ffffff", 130) if not dark else rgba("#ffffff", 28), shadow=False)
    d.text((box[0] + 32, box[1] + 33), title, font=font(29, "bold"), fill=rgba("#303845" if not dark else "#f1f6ff", 245))
    d.text((box[0] + 32, box[1] + 75), label, font=font(23), fill=rgba("#667284" if not dark else "#bac5d6", 245))


def meeting_card(base: Image.Image, box: tuple[int, int, int, int], dark: bool, expanded: bool) -> None:
    d = ImageDraw.Draw(base)
    x1, y1, x2, y2 = box
    fill = rgba("#d8eaff", 225) if not dark else rgba("#4868a3", 190)
    rounded_panel(base, box, 36, fill, rgba("#8dbdff", 160), 3, True)
    rounded_panel(base, (x1 + 28, y1 + 30, x1 + 82, y1 + 84), 15, rgba("#866eff", 68), shadow=False)
    d.text((x1 + 43, y1 + 42), "▣", font=font(22, "bold"), fill=rgba("#7564ff", 255))
    d.text((x1 + 104, y1 + 32), "NEXT MEETING", font=font(21, "bold"), fill=rgba("#6f7588" if not dark else "#c5caea", 255))
    d.text((x1 + 104, y1 + 65), "Design Sync", font=font(32, "bold"), fill=rgba("#172033" if not dark else "#ffffff", 255))
    d.text((x1 + 104, y1 + 108), "2:00 PM • in 10 min", font=font(26), fill=rgba("#536175" if not dark else "#ced7eb", 245))
    d.text((x2 - 155, y1 + 54), "…", font=font(28, "bold"), fill=rgba("#343b47" if not dark else "#e2e7f4", 230))
    d.text((x2 - 88, y1 + 52), "⌃", font=font(26, "bold"), fill=rgba("#687386" if not dark else "#cdd7ea", 230))
    if expanded:
        d.line((x1 + 44, y1 + 190, x2 - 44, y1 + 190), fill=rgba("#ffffff", 150) if not dark else rgba("#ffffff", 72), width=2)
        d.text((x1 + 44, y1 + 230), "Today's Plan", font=font(21, "bold"), fill=rgba("#796f88" if not dark else "#c6cbe4", 255))
        d.rounded_rectangle((x1 + 58, y1 + 292, x1 + 72, y1 + 370), 7, fill=rgba("#9b62ff", 255))
        d.text((x1 + 98, y1 + 284), "Design Sync", font=font(27, "bold"), fill=rgba("#1f2937" if not dark else "#ffffff", 245))
        d.text((x1 + 98, y1 + 323), "2:00 PM • in 10 min", font=font(23), fill=rgba("#6a7283" if not dark else "#cad4e7", 235))
        rounded_panel(base, (x2 - 166, y1 + 292, x2 - 112, y1 + 346), 17, rgba("#a66cff", 80), shadow=False)
        d.text((x2 - 151, y1 + 305), "▮", font=font(24, "bold"), fill=rgba("#9e65ff", 255))
        d.text((x2 - 82, y1 + 306), "♧", font=font(23), fill=rgba("#6f7789" if not dark else "#ccd6e7", 220))


def scroller(base: Image.Image, box: tuple[int, int, int, int], dark: bool) -> None:
    d = ImageDraw.Draw(base)
    x1, y1, x2, y2 = box
    rounded_panel(base, box, 30, rgba("#ffffff", 125) if not dark else rgba("#ffffff", 28), rgba("#ffffff", 76), 2, False)
    d.text((x1 + 34, y1 + 30), "Time Scroller", font=font(29, "bold"), fill=rgba("#313b48" if not dark else "#f5f8ff", 245))
    d.text((x1 + 212, y1 + 35), "(9:35 AM)", font=font(24, "bold"), fill=rgba("#6a7483" if not dark else "#b9c4d6", 230))
    d.text((x1 + 34, y1 + 71), "Scrub forward or backward across both clocks.", font=font(23), fill=rgba("#677385" if not dark else "#bbc6d8", 235))
    d.text((x2 - 112, y1 + 52), "Now", font=font(23, "bold"), fill=rgba("#6b7382" if not dark else "#c6d0e2", 240))
    track_y = y1 + 135
    d.rounded_rectangle((x1 + 34, track_y, x2 - 34, track_y + 10), 5, fill=rgba("#c3c9d5" if not dark else "#ffffff", 80))
    d.rounded_rectangle((x1 + 34, track_y, x1 + (x2 - x1) // 2, track_y + 10), 5, fill=rgba("#007aff", 255))
    d.ellipse((x1 + (x2 - x1) // 2 - 22, track_y - 18, x1 + (x2 - x1) // 2 + 22, track_y + 26), fill=rgba("#ffffff", 255))
    labels = ["-12h", "-9h", "-6h", "-3h", "Now", "+3h", "+6h", "+9h", "+12h"]
    for i, label in enumerate(labels):
        lx = int(x1 + 80 + i * ((x2 - x1 - 160) / (len(labels) - 1)))
        d.line((lx, track_y + 55, lx, track_y + 66), fill=rgba("#8893a5" if not dark else "#b4c0d3", 150), width=2)
        tw, _ = text_size(d, label, font(18, "bold" if label == "Now" else "regular"))
        d.text((lx - tw // 2, track_y + 82), label, font=font(18, "bold" if label == "Now" else "regular"), fill=rgba("#5f6a7b" if not dark else "#c7d1e1", 230))


def settings_window(base: Image.Image, box: tuple[int, int, int, int], dark: bool = True, selected: str = "Calendar") -> None:
    d = ImageDraw.Draw(base)
    rounded_panel(base, box, 34, rgba("#171b22", 238) if dark else rgba("#f6f8fb", 240), rgba("#ffffff", 58) if dark else rgba("#d7dce6", 255), 2, True)
    x1, y1, x2, y2 = box
    for i, c in enumerate(["#ff5f57", "#ffbd2e", "#28c840"]):
        d.ellipse((x1 + 28 + i * 34, y1 + 26, x1 + 48 + i * 34, y1 + 46), fill=rgba(c, 255))
    d.text((x1 + 600, y1 + 27), "Orpyt Settings", font=font(24, "bold"), fill=rgba("#cbd3df" if dark else "#4b5563", 235))
    sidebar = (x1 + 18, y1 + 80, x1 + 305, y2 - 20)
    d.rounded_rectangle(sidebar, 16, fill=rgba("#0d1118", 190) if dark else rgba("#ffffff", 160), outline=rgba("#ffffff", 35))
    items = ["Overview", "Time Zones", "Menu Bar", "Clock Details", "Calendar", "Weather", "Appearance"]
    y = y1 + 108
    for item in items:
        if item == selected:
            d.rounded_rectangle((x1 + 34, y - 12, x1 + 285, y + 50), 13, fill=rgba("#007aff", 255))
            fill = rgba("#ffffff", 255)
        else:
            fill = rgba("#d9e2ef" if dark else "#202936", 235)
        d.text((x1 + 70, y), item, font=font(25, "bold"), fill=fill)
        d.text((x1 + 42, y + 1), "✦" if item == "Overview" else "◌", font=font(20), fill=fill)
        y += 65
    cx = x1 + 365
    cy = y1 + 150
    d.text((cx, cy), selected, font=font(52, "bold"), fill=rgba("#f5f8ff" if dark else "#162032", 255))
    d.text((cx, cy + 68), "Choose how Orpyt fits your workflow.", font=font(30), fill=rgba("#aab5c4" if dark else "#637083", 235))
    rows = [
        ("Show next meeting", "Read your calendar and show it in the popover.", True),
        ("Next event", "Design Sync - 2:00 PM", False),
        ("Today's Plan", "Clickable events with join and copy actions.", True),
        ("Suggestions", "Send feature ideas to GitHub Discussions.", False),
    ]
    y = cy + 165
    for title, subtitle, on in rows:
        row_fill = rgba("#242d39", 255) if dark else rgba("#ffffff", 255)
        d.rounded_rectangle((cx, y, x2 - 55, y + 112), 20, fill=row_fill)
        d.text((cx + 32, y + 23), title, font=font(29, "bold"), fill=rgba("#f5f8ff" if dark else "#192232", 245))
        d.text((cx + 32, y + 65), subtitle, font=font(24), fill=rgba("#aeb9ca" if dark else "#667386", 235))
        if on:
            d.rounded_rectangle((x2 - 140, y + 39, x2 - 72, y + 75), 18, fill=rgba("#0a84ff", 255))
            d.ellipse((x2 - 105, y + 42, x2 - 75, y + 72), fill=rgba("#ffffff", 255))
        y += 134


def slide_01() -> Image.Image:
    img = background("dark")
    mac_menu_bar(img, "LON 9:35 AM | NYC 4:35 AM")
    d = ImageDraw.Draw(img)
    img.alpha_composite(app_icon(170), (124, 260))
    header_copy(img, "Menu bar world clock", "Two time zones.\nOne glance.", "See the time in your key cities instantly, right from your Mac menu bar.", 124, 500, 920, True)
    feature_pills(img, [("◎", "Multiple cities"), ("↯", "Instantly visible"), ("▭", "Native Mac")], 124, 1185, True)
    popover(img, (1540, 210, 2660, 1635), dark=True, expanded=False)
    return img


def slide_02() -> Image.Image:
    img = background("light")
    mac_menu_bar(img, "LON 9:35 AM | NYC 4:35 AM", "10m")
    header_copy(img, "Calendar intelligence", "Meetings,\nwithout surprise.", "Meeting alerts, Today's Plan, join links, and copy actions without leaving the menu bar.", 128, 410, 920, False)
    popover(img, (1280, 150, 2600, 1390), dark=False, expanded=True, footer=False)
    return img


def slide_03() -> Image.Image:
    img = background("dark")
    mac_menu_bar(img, "LON 2:00 PM | NYC 9:00 AM")
    header_copy(img, "Plan better meetings", "Find a time\nthat works.", "Use Time Scroller to scrub across zones and spot friendlier meeting hours before you send the invite.", 140, 330, 930, True)
    popover(img, (1390, 170, 2570, 1325), dark=True, expanded=False, footer=False)
    d = ImageDraw.Draw(img)
    rounded_panel(img, (1560, 1180, 2440, 1455), 36, rgba("#111d34", 220), rgba("#77baff", 84), 2, True)
    d.text((1618, 1234), "Time Scroller", font=font(42, "bold"), fill=rgba("#ffffff", 255))
    d.text((1618, 1296), "London 2:00 PM  ·  New York 9:00 AM", font=font(30), fill=rgba("#bbcae3", 245))
    d.rounded_rectangle((1618, 1378, 2378, 1390), 6, fill=rgba("#ffffff", 80))
    d.rounded_rectangle((1618, 1378, 2000, 1390), 6, fill=rgba("#0a84ff", 255))
    d.ellipse((1976, 1353, 2024, 1401), fill=rgba("#ffffff", 255))
    return img


def slide_04() -> Image.Image:
    img = background("light")
    mac_menu_bar(img, "CHI 12:25 PM | KHI 10:25 PM")
    header_copy(img, "Weather context", "Before you message,\nknow the day.", "Live weather on each clock helps you read the room across countries and schedules.", 132, 390, 930, False)
    popover(img, (1180, 145, 2560, 1540), dark=False, expanded=False, footer=True)
    d = ImageDraw.Draw(img)
    rounded_panel(img, (180, 1110, 1070, 1405), 46, rgba("#ffffff", 245), rgba("#c7dfff", 210), 2, True)
    weather_sun(d, 245, 1260, rgba("#ffbd3d", 255))
    d.text((385, 1205), "20°C • Mostly Sunny", font=font(46, "bold"), fill=rgba("#142033", 255))
    d.text((385, 1278), "New York • Feels like 21°C", font=font(32), fill=rgba("#5a6677", 245))
    d.text((385, 1338), "Weather stays visible beside each clock.", font=font(27, "bold"), fill=rgba("#007aff", 245))
    return img


def slide_05() -> Image.Image:
    img = background("dark")
    mac_menu_bar(img, "LON 10:06 AM | NYC 5:06 AM")
    header_copy(img, "Native controls", "Make Orpyt\nwork your way.", "Choose visible clocks, clock format, weather, calendar, and menu bar behavior from one clean settings window.", 124, 285, 870, True)
    settings_window(img, (1110, 180, 2705, 1585), dark=True, selected="Menu Bar")
    d = ImageDraw.Draw(img)
    feature_pills(img, [("12h", "Format"), ("☁", "Weather"), ("▣", "Calendar")], 124, 1160, True)
    return img


def slide_06() -> Image.Image:
    img = background("light")
    mac_menu_bar(img, "LON 9:35 AM | NYC 4:35 AM")
    img.alpha_composite(app_icon(150), (138, 210))
    header_copy(img, "Free to start", "A calm Mac app\nfor global work.", "Dual clocks are always free. Pro adds weather, calendar context, and planning tools when your workday needs more.", 136, 430, 980, False)
    feature_pills(img, [("✓", "Free clocks"), ("☁", "Pro weather"), ("▣", "Pro calendar")], 136, 1180, False)
    popover(img, (1420, 100, 2605, 1400), dark=False, expanded=True, footer=False)
    return img


def save_all() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    slides = [
        ("01-menu-bar-glance.png", slide_01()),
        ("02-free-to-start.png", slide_06()),
        ("03-time-scroller.png", slide_03()),
        ("04-calendar-plan.png", slide_02()),
        ("05-weather-context.png", slide_04()),
        ("06-customize-settings.png", slide_05()),
    ]
    for name, image in slides:
        image.convert("RGB").save(OUT / name, "PNG", optimize=True)
        print(OUT / name)


if __name__ == "__main__":
    save_all()
