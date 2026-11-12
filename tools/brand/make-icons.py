"""Builds the Android launcher icons and the in-app logo from the brand sources in brand/.

  python tools/brand/make-icons.py

Sources (generated with Codex image generation, docs/design-language.md):
  brand/lexona-icon.png       square icon on its ink background (legacy launcher icon)
  brand/lexona-icon-fg.png    the same mascot on transparency (adaptive foreground, in-app logo)
The one-colour layer (themed icons) is the foreground's silhouette in white.
"""
import pathlib
import sys

from PIL import Image, ImageChops

ROOT = pathlib.Path(__file__).resolve().parents[2]
BRAND = ROOT / "brand"
RES = ROOT / "app/android/app/src/main/res"
INK = (11, 19, 43, 255)  # #0B132B, the icon background

# dp 48 for legacy icons, dp 108 for adaptive layers.
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def trimmed(image):
    """The mascot cropped to its visible pixels; faint stray pixels of the generator dropped."""
    alpha = image.getchannel("A").point(lambda a: 0 if a < 24 else a)
    image.putalpha(alpha)
    box = alpha.getbbox()
    return image.crop(box) if box else image


def on_canvas(mascot, size, share, background=None):
    """mascot scaled so its longer side is `share` of a size x size canvas, centered."""
    canvas = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))
    scale = size * share / max(mascot.size)
    scaled = mascot.resize((max(1, round(mascot.width * scale)), max(1, round(mascot.height * scale))),
                           Image.LANCZOS)
    canvas.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return canvas


def main():
    fg_source = BRAND / "lexona-icon-fg.png"
    if not fg_source.is_file():
        sys.exit(f"missing {fg_source}")
    mascot = trimmed(Image.open(fg_source).convert("RGBA"))
    # Themed icon: the coloured areas in white, the dark outline left out, so the eye, the
    # stripes and the screen still read as shapes.
    mono = Image.new("RGBA", mascot.size, (255, 255, 255, 255))
    light = mascot.convert("L").point(lambda v: 255 if v > 70 else 0)
    mono.putalpha(ImageChops.darker(light, mascot.getchannel("A")))

    for name, factor in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        legacy = round(48 * factor)
        # Legacy icon: launchers mask it to a circle or squircle, keep the mascot inside 72 %.
        on_canvas(mascot, legacy, 0.72, INK).save(folder / "launcher_icon.png")
        layer = round(108 * factor)
        # Adaptive layers: the visible area is the central 72 of 108 dp; the mascot fills ~60 dp.
        on_canvas(mascot, layer, 0.56).save(folder / "launcher_icon_foreground.png")
        if mono:
            on_canvas(mono, layer, 0.56).save(folder / "launcher_icon_monochrome.png")
            # Notification icon: 24 dp, white on transparency (Android tints it).
            drawable = RES / f"drawable-{name}"
            drawable.mkdir(exist_ok=True)
            on_canvas(mono, round(24 * factor), 0.92).save(drawable / "ic_stat_lexona.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    mono_line = '    <monochrome android:drawable="@mipmap/launcher_icon_monochrome" />\n' if mono else ""
    (anydpi / "launcher_icon.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/launcher_icon_background" />\n'
        '    <foreground android:drawable="@mipmap/launcher_icon_foreground" />\n'
        f"{mono_line}"
        "</adaptive-icon>\n", encoding="utf-8", newline="\n")
    (RES / "values/launcher_icon_colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="launcher_icon_background">#0B132B</color>\n</resources>\n',
        encoding="utf-8", newline="\n")

    # In-app logo (welcome and home screens): the mascot alone, 512 px.
    on_canvas(mascot, 512, 0.94).save(ROOT / "app/assets/icons/logo.png")
    wallpaper(mascot).save(ROOT / "app/android/app/src/main/assets/droiddesk/lexona-wallpaper.jpg",
                           quality=90, optimize=True, progressive=True)
    print("icons and wallpaper written")


def wallpaper(mascot, width=3840, height=2160):
    """Desktop wallpaper: ink with a soft teal glow in the centre, the mascot small at the
    bottom centre, the sides calm for the desktop icons and the dock."""
    small = (width // 8, height // 8)
    glow = Image.new("RGB", small)
    cx, cy, radius = small[0] * 0.5, small[1] * 0.5, small[0] * 0.55
    pixels = glow.load()
    for y in range(small[1]):
        for x in range(small[0]):
            t = max(0.0, 1.0 - (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / radius)
            t = t * t * 0.55
            # ink #0B132B towards deep teal #0F4C5C
            pixels[x, y] = (round(11 + (15 - 11) * t), round(19 + (76 - 19) * t), round(43 + (92 - 43) * t))
    image = glow.resize((width, height), Image.BICUBIC).convert("RGBA")
    corner = on_canvas(mascot, round(height * 0.16), 1.0)
    # xfdesktop zooms the image to fill the screen and crops the rest: on a 16:10 tablet the
    # mascot at the right edge was cut off, and a phone in portrait shows only the middle
    # quarter of the width. So the mascot sits at the bottom centre, visible on every shape.
    bottom = round(height * 0.92)
    image.alpha_composite(corner, ((width - corner.width) // 2, bottom - corner.height))
    return image.convert("RGB")


if __name__ == "__main__":
    main()
