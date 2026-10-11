"""Rewrites the generated web and macOS icons with rounded corners.

The source artwork (assets/images/branding/mooncalendar_icon.png) is never modified; the rounded
versions are rendered from it. Maskable web icons and iOS icons stay square on purpose: the
platform applies its own mask there.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

SOURCE = "assets/images/branding/mooncalendar_icon.png"
RADIUS = 0.2237  # corner radius as a fraction of the icon size (the macOS / iOS shape)


def rounded(size, margin=0.0):
    """Source icon scaled to `size`, with rounded corners and an optional transparent margin."""
    src = Image.open(SOURCE).convert("RGBA")
    inner = max(1, round(size * (1 - 2 * margin)))
    scale = 4
    mask = Image.new("L", (inner * scale, inner * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, inner * scale - 1, inner * scale - 1), radius=inner * scale * RADIUS, fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    art = src.resize((inner, inner), Image.LANCZOS)
    art.putalpha(mask)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - inner) // 2
    canvas.paste(art, (offset, offset), art)
    return canvas


def rewrite(path, margin=0.0):
    if not os.path.exists(path):
        return
    size = Image.open(path).size[0]
    rounded(size, margin).save(path)
    print("rounded", path)


# Web: favicon and the regular (non-maskable) PWA icons.
rewrite("web/favicon.png")
for p in glob.glob("web/icons/Icon-*.png"):
    if "maskable" not in p:
        rewrite(p)

# macOS: rounded shape with the standard transparent margin.
for p in glob.glob("macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png"):
    rewrite(p, margin=0.098)


if __name__ == "__main__" and "--linux" in sys.argv:
    # Linux window icon, bundled as the Flutter asset mooncalendar_icon_round.png.
    rounded(512).save("assets/images/branding/mooncalendar_icon_round.png")
