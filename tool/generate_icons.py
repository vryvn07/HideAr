"""Generates HideAr's icons.

    python tool/generate_icons.py

Writes:
    windows/runner/resources/app_icon.ico   executable, window and taskbar icon
    assets/tray_icon.ico                    notification-area icon
    docs/icon.png                           website and README

The mark is a warm-beige card framed in deep espresso brown with a veiled
shutter bar and caramel lens dot inside, drawn on a 16-unit grid so every size
stays crisp from 16 px in the system tray up to 256 px.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ESPRESSO = (44, 27, 18, 255)   # #2C1B12
BEIGE = (245, 239, 230, 255)   # #F5EFE6
SAND = (227, 214, 195, 255)    # #E3D6C3
CARAMEL = (158, 90, 42, 255)   # #9E5A2A

# (x0, y0, x1, y1) in 16-unit grid space, end-exclusive, painted in order.
SHAPES = [
    ((1, 1, 15, 15), ESPRESSO),  # squircle body
    ((0, 3, 16, 13), ESPRESSO),  # horizontal pill edge
    ((3, 0, 13, 16), ESPRESSO),  # vertical pill edge
    ((2, 3, 14, 13), BEIGE),     # warm beige inner plate
    ((3, 2, 13, 14), BEIGE),     # warm beige vertical fill
    ((4, 4, 12, 6), SAND),       # subtle upper bevel
    ((4, 6, 12, 10), ESPRESSO),  # dark espresso visor band
    ((5, 10, 11, 12), ESPRESSO), # shield taper
    ((7, 7, 9, 9), CARAMEL),     # caramel indicator core
]

ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 256]

ROOT = Path(__file__).resolve().parent.parent


def render(size: int) -> Image.Image:
    """Renders the mark at [size] px with every edge on a whole pixel."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def edge(v: int) -> int:
        return round(v * size / 16)

    for (x0, y0, x1, y1), colour in SHAPES:
        left, top = edge(x0), edge(y0)
        right, bottom = max(edge(x1), left + 1), max(edge(y1), top + 1)
        draw.rectangle((left, top, right - 1, bottom - 1), fill=colour)
    return img


def write_ico(path: Path) -> None:
    frames = [render(s) for s in ICO_SIZES]
    path.parent.mkdir(parents=True, exist_ok=True)
    frames[-1].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=frames[:-1],
    )
    print(f"wrote {path.relative_to(ROOT)}  ({', '.join(map(str, ICO_SIZES))} px)")


def main() -> None:
    write_ico(ROOT / "windows" / "runner" / "resources" / "app_icon.ico")
    write_ico(ROOT / "assets" / "tray_icon.ico")
    png = ROOT / "docs" / "icon.png"
    render(256).save(png)
    print(f"wrote {png.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
