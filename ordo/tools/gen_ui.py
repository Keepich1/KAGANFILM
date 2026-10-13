"""Рисованный интерфейс «Города» (ТЗ §12, ARCHITECTURE §14, §19.6): одна «рука» с остальными текстурами.

Материалы: орех (резное дерево), латунь с заклёпками, «самаркандская бумага», кожа вкладок;
пояса-орнаменты нижней панели (Коканд — бирюзовые изразцы с восьмиконечными звёздами, кыпчаки —
красный войлок с «кочкор мүйүз»); сургучные печати (красная, зелёная, золотая); курсор-наконечник
стрелы; значки ресурсов, приказов, родов войск и построек — «гравировка» по маске (золочёная
заливка, тёмный контур, тень).

    cd ordo && python3 tools/gen_ui.py          # → assets/ui/*.png, assets/ui/icons/*.png

Детерминировано (seed). Размеры — под холст 1920×1080 (окно растягивается canvas_items).
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paint import Canvas, fbm, ram_horn  # noqa: E402
from palette import KIPCHAK, KOKAND, MATERIAL, rgb8  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "ui")
ICONS = os.path.join(OUT, "icons")

WALNUT = ["#4a2f1c", "#5a3b24", "#3c2416", "#6a4429"]
BRASS = {"hi": "#f2d68a", "mid": "#c49a48", "lo": "#7a5422", "deep": "#3e2a12"}
PAPER = ["#e9d9b4", "#e2cfa4", "#efe2c2", "#d9c398"]
INK = "#2b1a10"


def save(img: Image.Image, name: str, folder: str = OUT) -> None:
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name), optimize=True)


def arr(img: Image.Image) -> np.ndarray:
    return np.asarray(img, dtype=np.float64)


def from_arr(a: np.ndarray, mode: str = "RGB") -> Image.Image:
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), mode)


# ================================================================= материалы

def walnut(w: int, h: int, seed: int, tone: float = 1.0, tile: bool = True) -> Image.Image:
    """Орех: тёмная подмалёвка, длинные мазки волокон вдоль x, свили (сучки)."""
    c = Canvas(w, h, base=WALNUT[1], seed=seed, tile=tile)
    c.underpaint(WALNUT, cell=max(24, h // 2), octaves=3)
    c.strokes(int(w * h / 90), ["#6e4a2c", "#3a2314", "#7a5232", "#2e1b10"], length=(w * 0.08, w * 0.3),
              width=(1.2, 3.2), angle=0, angle_jitter=1.5, alpha=(0.18, 0.45), curve=0.05, bristles=3, taper=0.3)
    rs = np.random.default_rng(seed + 3)
    for _ in range(max(1, w * h // 60000)):
        x, y = rs.uniform(0, w), rs.uniform(0, h)
        for k in range(5):
            c.ellipse(x, y, 10 - k * 1.6, 4 - k * 0.6, "#2e1b10" if k % 2 == 0 else "#6a4429", 0.35)
    c.grain(0.05)
    img = c.image()
    if tone != 1.0:
        img = from_arr(arr(img) * tone)
    return img


def paper(w: int, h: int, seed: int, tone: float = 1.0) -> Image.Image:
    """«Самаркандская бумага»: тёплый кремовый, волокна, пятна, темнее к краям."""
    c = Canvas(w, h, base=PAPER[0], seed=seed, tile=False)
    c.underpaint(PAPER, cell=max(32, min(w, h) // 3), octaves=4)
    c.strokes(int(w * h / 260), ["#f4e8cc", "#d4bd8e", "#e6d3a8"], length=(6, 22), width=(0.6, 1.4),
              angle=lambda x, y: (x * 7 + y * 13) % 180, angle_jitter=60, alpha=(0.15, 0.4), curve=0.6, bristles=1)
    c.grain(0.035, cell=1.2)
    img = c.image()
    a = arr(img)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float64)
    edge = np.clip(d / max(8.0, min(w, h) * 0.12), 0, 1) ** 0.6
    n = fbm(w, h, cell=max(16, min(w, h) // 4), octaves=3, seed=seed + 9, tile=False)
    shade = (0.78 + 0.22 * edge) * (0.94 + 0.08 * n)
    a = a * shade[..., None] * tone
    return from_arr(a)


def deckle(w: int, h: int, seed: int, rough: float = 5.0, inset: float = 3.0) -> np.ndarray:
    """Альфа с рваным краем бумаги (0..1)."""
    n = fbm(w, h, cell=12, octaves=3, seed=seed, tile=False)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float64)
    return np.clip((d - inset - rough * n) / 1.6, 0, 1)


def brass_band(img: Image.Image, box: tuple, width: int, rivets: bool = True, seed: int = 0) -> None:
    """Латунная рама по прямоугольнику box (x0, y0, x1, y1) шириной width: свет сверху-слева, тень снизу."""
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box
    for i in range(width):
        t = i / max(1, width - 1)
        # профиль: тёмная кромка → светлая грань → середина → тень → тёмная кромка
        prof = 0.55 + 0.6 * math.sin(math.pi * min(1.0, t * 1.15)) - (0.35 if t > 0.85 else 0.0)
        base = np.array(rgb8(BRASS["mid"]), float) * prof
        top = tuple(int(v) for v in np.clip(base * 1.18, 0, 255)) + (255,)
        bot = tuple(int(v) for v in np.clip(base * 0.72, 0, 255)) + (255,)
        d.line([(x0 + i, y0 + i), (x1 - i, y0 + i)], fill=top)
        d.line([(x0 + i, y0 + i), (x0 + i, y1 - i)], fill=top)
        d.line([(x0 + i, y1 - i), (x1 - i, y1 - i)], fill=bot)
        d.line([(x1 - i, y0 + i), (x1 - i, y1 - i)], fill=bot)
    d.rectangle([x0, y0, x1, y1], outline=rgb8(BRASS["deep"]) + (255,))
    d.rectangle([x0 + width, y0 + width, x1 - width, y1 - width], outline=rgb8(BRASS["deep"]) + (200,))
    # потёртости латуни
    rs = np.random.default_rng(seed)
    for _ in range(int((x1 - x0 + y1 - y0) * 0.4)):
        side = rs.integers(4)
        if side < 2:
            x = rs.uniform(x0, x1)
            y = y0 + rs.uniform(0, width) if side == 0 else y1 - rs.uniform(0, width)
        else:
            y = rs.uniform(y0, y1)
            x = x0 + rs.uniform(0, width) if side == 2 else x1 - rs.uniform(0, width)
        col = BRASS["hi"] if rs.random() < 0.5 else BRASS["lo"]
        d.point((x, y), fill=rgb8(col) + (int(rs.uniform(60, 140)),))
    if rivets:
        r = max(2.5, width * 0.32)
        for cx, cy in [(x0 + width / 2, y0 + width / 2), (x1 - width / 2, y0 + width / 2),
                       (x0 + width / 2, y1 - width / 2), (x1 - width / 2, y1 - width / 2)]:
            rivet(img, cx, cy, r)


def rivet(img: Image.Image, cx: float, cy: float, r: float) -> None:
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([cx - r - 1, cy - r, cx + r + 1, cy + r + 1.5], fill=(20, 12, 6, 160))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb8(BRASS["lo"]) + (255,))
    d.ellipse([cx - r * 0.8, cy - r * 0.85, cx + r * 0.55, cy + r * 0.5], fill=rgb8(BRASS["mid"]) + (255,))
    d.ellipse([cx - r * 0.55, cy - r * 0.6, cx - r * 0.05, cy - r * 0.1], fill=rgb8(BRASS["hi"]) + (230,))


def bevel(img: Image.Image, box: tuple, depth: int, inset: bool = False, strength: float = 0.5) -> None:
    """Резная фаска по дереву: светлая сверху-слева, тёмная снизу-справа (inset — наоборот)."""
    a = arr(img.convert("RGB"))
    x0, y0, x1, y1 = box
    for i in range(depth):
        k = strength * (1 - i / depth)
        hi, lo = (1 + k * 0.6), (1 - k * 0.7)
        if inset:
            hi, lo = lo, hi
        a[y0 + i, x0 + i:x1 - i] *= hi
        a[y0 + i:y1 - i, x0 + i] *= hi
        a[y1 - 1 - i, x0 + i:x1 - i] *= lo
        a[y0 + i:y1 - i, x1 - 1 - i] *= lo
    out = from_arr(a)
    if img.mode == "RGBA":
        out.putalpha(img.getchannel("A"))
    img.paste(out)


# ================================================================= панели (9-slice)

def gen_beam() -> None:
    """Верхняя балка: орех, латунная полоса снизу, тёмная кромка сверху. Плитка по x (512)."""
    w, h = 512, 64
    img = walnut(w, h, seed=11, tone=1.05)
    bevel(img, (0, 0, w, h - 8), 5, strength=0.45)
    d = ImageDraw.Draw(img, "RGBA")
    # латунная полоса снизу
    for i in range(8):
        t = i / 7
        c = np.array(rgb8(BRASS["mid"]), float) * (1.15 - 0.55 * t)
        d.line([(0, h - 8 + i), (w, h - 8 + i)], fill=tuple(int(v) for v in np.clip(c, 0, 255)) + (255,))
    d.line([(0, h - 9), (w, h - 9)], fill=rgb8(BRASS["deep"]) + (255,))
    d.line([(0, h - 1), (w, h - 1)], fill=(18, 10, 5, 255))
    for x in range(16, w, 64):
        rivet(img, x, h - 4.2, 2.6)
    # резьба: тонкий желобок по балке
    d.line([(0, 9), (w, 9)], fill=(25, 14, 8, 150), width=2)
    d.line([(0, 11), (w, 11)], fill=(150, 105, 64, 70), width=1)
    save(img, "beam.png")


def gen_panel() -> None:
    """Ореховая панель с резной фаской и латунным уголком: 9-slice 256, поля 22."""
    w = h = 256
    img = walnut(w, h, seed=21)
    bevel(img, (0, 0, w, h), 6, strength=0.5)
    bevel(img, (10, 10, w - 10, h - 10), 3, inset=True, strength=0.35)
    img = img.convert("RGBA")
    for cx, cy in [(9, 9), (w - 9, 9), (9, h - 9), (w - 9, h - 9)]:
        rivet(img, cx, cy, 3.4)
    save(img, "panel.png")
    # тёмная вставка (подложка миникарты, карточек)
    w2 = h2 = 128
    img2 = walnut(w2, h2, seed=23, tone=0.62)
    bevel(img2, (0, 0, w2, h2), 4, inset=True, strength=0.6)
    save(img2, "inset.png")


def gen_frames() -> None:
    """Латунная рама с заклёпками (прозрачная середина): 9-slice 128, поля 14."""
    w = h = 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    brass_band(img, (0, 0, w - 1, h - 1), 10, rivets=True, seed=5)
    save(img, "frame_brass.png")
    # тонкая рама для кнопок и карточек
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    brass_band(img, (0, 0, 63, 63), 5, rivets=False, seed=7)
    save(img, "frame_thin.png")


def gen_paper() -> None:
    img = paper(512, 384, seed=31)
    save(img, "paper.png")
    # старая карта: темнее, пятна, «выгоревшая» сепия
    m = paper(256, 256, seed=33, tone=0.92)
    a = arr(m)
    n = fbm(256, 256, cell=48, octaves=4, seed=34, tile=False)
    stain = np.clip((n - 0.62) * 3.0, 0, 1)[..., None]
    a = a * (1 - 0.25 * stain) + np.array(rgb8("#8a6a3a"), float) * 0.25 * stain
    save(from_arr(a), "map_paper.png")


def gen_buttons() -> None:
    """Квадратная кнопка: ореховая плашка в латунном ободке. 96, поля 16."""
    s = 96
    states = {"normal": (1.0, 0.0, False), "hover": (1.18, 0.35, False), "pressed": (0.78, 0.0, True),
              "disabled": (0.6, 0.0, False), "active": (1.1, 0.6, True)}
    base = walnut(s, s, seed=41, tone=1.0)
    for name, (tone, glow, inset) in states.items():
        img = from_arr(arr(base) * tone).convert("RGBA")
        bevel(img, (6, 6, s - 6, s - 6), 5, inset=inset, strength=0.55)
        brass_band(img, (0, 0, s - 1, s - 1), 6, rivets=False, seed=43)
        if glow > 0:
            d = ImageDraw.Draw(img, "RGBA")
            for i in range(6):
                d.rectangle([6 + i, 6 + i, s - 7 - i, s - 7 - i], outline=rgb8("#ffd27a") + (int(90 * glow * (1 - i / 6)),))
        if name == "disabled":
            a = arr(img.convert("RGB"))
            g = a.mean(axis=2, keepdims=True)
            a = a * 0.35 + g * 0.65
            img = from_arr(a).convert("RGBA")
        save(img, f"button_{name}.png")


def gen_tabs() -> None:
    """Вкладки «Приказы / Хозяйство / Укрепления»: кожаный язычок с латунной кромкой. 160×44, поля 16."""
    w, h = 160, 44
    for name, (col, tone) in {"tab": ("#5e3a22", 0.85), "tab_active": ("#8a5a32", 1.05),
                              "tab_hover": ("#6e4428", 0.95)}.items():
        c = Canvas(w, h, base=col, seed=51, tile=False)
        c.underpaint([col, "#4a2a18", "#7a4e2c"], cell=24, octaves=2)
        c.strokes(220, ["#2e1a0e", "#9a6a40"], length=(4, 12), width=(1, 2.5), angle=0, angle_jitter=80,
                  alpha=(0.1, 0.3), curve=0.5, bristles=1)
        img = from_arr(arr(c.image()) * tone).convert("RGBA")
        # язычок: скруглённые верхние углы, прошивка по краю
        mask = Image.new("L", (w, h), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle([0, 0, w - 1, h + 12], radius=12, fill=255)
        img.putalpha(mask)
        d = ImageDraw.Draw(img, "RGBA")
        for x in range(10, w - 10, 7):
            d.line([(x, 5), (x + 3, 5)], fill=rgb8("#d8b880") + (150,), width=1)
        edge = BRASS["hi"] if name == "tab_active" else BRASS["lo"]
        d.rounded_rectangle([0, 0, w - 1, h + 12], radius=12, outline=rgb8(edge) + (255,), width=2)
        save(img, f"{name}.png")


def gen_plaque() -> None:
    """Табличка таймера набега: свиток бумаги на ореховой подложке с латунными уголками. 9-slice 360×72, поля 28."""
    w, h = 360, 72
    img = walnut(w, h, seed=61, tone=0.9).convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon([(0, 0), (w, 0), (w - 18, h - 1), (18, h - 1)], fill=255)
    img.putalpha(mask)
    p = paper(w - 56, h - 18, seed=62).convert("RGBA")
    p.putalpha(from_arr(deckle(w - 56, h - 18, seed=63, rough=3, inset=1) * 255, "L"))
    img.alpha_composite(p, (28, 6))
    d = ImageDraw.Draw(img, "RGBA")
    d.line([(0, 0), (18, h - 1)], fill=rgb8(BRASS["mid"]) + (255,), width=3)
    d.line([(w - 1, 0), (w - 19, h - 1)], fill=rgb8(BRASS["mid"]) + (255,), width=3)
    d.line([(18, h - 2), (w - 19, h - 2)], fill=rgb8(BRASS["lo"]) + (255,), width=3)
    rivet(img, 14, 10, 3.2)
    rivet(img, w - 14, 10, 3.2)
    save(img, "plaque.png")


def gen_note() -> None:
    """Записка: полоска бумаги с рваным краем и тенью. 9-slice 400×76, поля 26."""
    w, h = 400, 76
    p = paper(w - 8, h - 8, seed=71)
    al = deckle(w - 8, h - 8, seed=72, rough=4.5, inset=1.5)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.fromarray((al * 120).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(3))
    shadow = Image.new("RGBA", (w - 8, h - 8), (20, 10, 4, 255))
    shadow.putalpha(sh)
    img.alpha_composite(shadow, (6, 7))
    pr = p.convert("RGBA")
    pr.putalpha(from_arr(al * 255, "L"))
    img.alpha_composite(pr, (2, 2))
    save(img, "note.png")


def gen_card() -> None:
    """Карточка отряда: бумага потемнее с тонкой рамкой тушью. 9-slice 128, поля 12."""
    s = 128
    p = paper(s, s, seed=81, tone=0.93).convert("RGBA")
    d = ImageDraw.Draw(p, "RGBA")
    d.rectangle([3, 3, s - 4, s - 4], outline=rgb8(INK) + (170,), width=2)
    d.rectangle([7, 7, s - 8, s - 8], outline=rgb8(INK) + (70,), width=1)
    save(p, "card.png")


# ================================================================= пояса-орнаменты

def gen_belt_kokand() -> None:
    """Бирюзовые изразцы: восьмиконечные звёзды и кресты, золотой кант. Плитка 288×36 (8 изразцов)."""
    th = 36
    n = 8
    ss = 4
    W, H = th * n * ss, th * ss
    img = Image.new("RGB", (W, H), rgb8(KOKAND["tile"]))
    base = Canvas(th * n, th, base=KOKAND["tile"], seed=91, tile=True)
    base.underpaint([KOKAND["tile"], "#33b3a8", "#1f8d86", "#2aa39a"], cell=18, octaves=2)
    base.grain(0.05)
    img = base.image().resize((W, H), Image.BICUBIC)
    d = ImageDraw.Draw(img, "RGBA")
    deep = rgb8(KOKAND["tile_deep"])
    gold = rgb8(KOKAND["gold"])
    cream = rgb8("#f1e6c8")
    band = 4 * ss
    for i in range(n):
        cx, cy = (i + 0.5) * th * ss, H / 2
        r = (th / 2 - 5) * ss
        # восьмиконечная звезда: два квадрата
        sq1 = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in [k * math.pi / 2 + math.pi / 4 for k in range(4)]]
        sq2 = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in [k * math.pi / 2 for k in range(4)]]
        d.polygon(sq1, fill=deep + (255,))
        d.polygon(sq2, fill=deep + (255,))
        r2 = r * 0.74
        sq1 = [(cx + r2 * math.cos(a), cy + r2 * math.sin(a)) for a in [k * math.pi / 2 + math.pi / 4 for k in range(4)]]
        sq2 = [(cx + r2 * math.cos(a), cy + r2 * math.sin(a)) for a in [k * math.pi / 2 for k in range(4)]]
        d.polygon(sq1, fill=cream + (255,))
        d.polygon(sq2, fill=cream + (255,))
        rr = r * 0.34
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=gold + (255,))
        d.ellipse([cx - rr * 0.45, cy - rr * 0.45, cx + rr * 0.45, cy + rr * 0.45], fill=deep + (255,))
        # кресты между звёздами
        x = (i + 1) * th * ss
        k = th * 0.16 * ss
        d.polygon([(x, cy - k * 1.6), (x + k * 0.55, cy - k * 0.55), (x + k * 1.6, cy), (x + k * 0.55, cy + k * 0.55),
                   (x, cy + k * 1.6), (x - k * 0.55, cy + k * 0.55), (x - k * 1.6, cy), (x - k * 0.55, cy - k * 0.55)],
                  fill=gold + (230,))
        # швы изразцов
        d.line([(i * th * ss, band), (i * th * ss, H - band)], fill=(16, 60, 58, 120), width=ss)
    for x in [0, W]:
        pass
    # золотой кант сверху и снизу с тёмной кромкой
    d.rectangle([0, 0, W, band], fill=gold + (255,))
    d.rectangle([0, H - band, W, H], fill=gold + (255,))
    d.line([(0, band), (W, band)], fill=deep + (255,), width=ss)
    d.line([(0, H - band), (W, H - band)], fill=deep + (255,), width=ss)
    d.line([(0, ss), (W, ss)], fill=rgb8("#f2d68a") + (200,), width=ss)
    img = img.resize((th * n, th), Image.LANCZOS)
    # глазурь: блик сверху
    a = arr(img)
    t = np.linspace(1.12, 0.86, th)[:, None, None]
    save(from_arr(a * t), "belt_kokand.png")


def gen_belt_kipchak() -> None:
    """Красный войлок с «кочкор мүйүз» (белые бараньи рога), тёмные полосы и стежки. Плитка 288×36."""
    w, h = 288, 36
    ss = 4
    c = Canvas(w * ss, h * ss, base=KIPCHAK["main"], seed=95, ss=1, tile=True)
    c.underpaint([KIPCHAK["main"], "#a1322a", "#bd4236", KIPCHAK["carmine"]], cell=24 * ss, octaves=3)
    c.strokes(2600, ["#c24a3c", "#8a2a22", "#a83a30"], length=(3 * ss, 9 * ss), width=(0.8 * ss, 1.8 * ss),
              angle=0, angle_jitter=90, alpha=(0.15, 0.4), curve=0.8, bristles=1)
    band = 4 * ss
    dark = KIPCHAK["dark"]
    c.rect(0, 0, w * ss, band, dark)
    c.rect(0, h * ss - band, w * ss, h * ss, dark)
    n = 6
    for i in range(n):
        cx = (i + 0.5) * w * ss / n
        ram_horn(c, cx, h * ss * 0.52, h * ss * 0.62, KIPCHAK["felt"], 2.4 * ss, 1.0, seed=i)
        # ромбик между рогами
        x = (i + 1) * w * ss / n
        r = 3.2 * ss
        c.polygon([(x, h * ss / 2 - r), (x + r, h * ss / 2), (x, h * ss / 2 + r), (x - r, h * ss / 2)],
                  KIPCHAK["felt"], 0.95, wobble=0.6)
    img = c.image().resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(img, "RGBA")
    for x in range(0, w, 6):
        d.line([(x, 5), (x + 3, 5)], fill=rgb8(KIPCHAK["felt"]) + (150,), width=1)
        d.line([(x + 2, h - 6), (x + 5, h - 6)], fill=rgb8(KIPCHAK["felt"]) + (150,), width=1)
    a = arr(img)
    t = np.linspace(1.08, 0.88, h)[:, None, None]
    save(from_arr(a * t), "belt_kipchak.png")


# ================================================================= печати и курсоры

def star_points(cx, cy, r_out, r_in, n=8, rot=-math.pi / 2):
    pts = []
    for k in range(n * 2):
        r = r_out if k % 2 == 0 else r_in
        a = rot + k * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def gen_seals() -> None:
    """Сургучные печати 64×64: капля сургуча с наплывами и выдавленной восьмиконечной звездой."""
    s, ss = 64, 4
    S = s * ss
    cols = {"red": ("#9a2018", "#5c0f0b", "#d65a44"), "green": ("#2f6b3a", "#173a1e", "#6aa86a"),
            "gold": ("#b8862a", "#6a4612", "#f0c860")}
    for name, (mid, dark, hi) in cols.items():
        rs = np.random.default_rng(hash(name) % 1000)
        mask = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(mask)
        cx = cy = S / 2
        pts = []
        for k in range(48):
            a = k / 48 * 2 * math.pi
            r = S * 0.40 * (1 + 0.06 * math.sin(a * 5 + 1.3) + 0.04 * rs.normal())
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        md.polygon(pts, fill=255)
        for _ in range(4):
            a = rs.uniform(0, 2 * math.pi)
            r = S * 0.4
            md.ellipse([cx + r * math.cos(a) - S * 0.06, cy + r * math.sin(a) - S * 0.06,
                        cx + r * math.cos(a) + S * 0.06, cy + r * math.sin(a) + S * 0.06], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(ss * 0.8)).point(lambda v: 255 if v > 128 else 0)
        m = np.asarray(mask, dtype=np.float64) / 255
        # объём: освещение по размытой маске
        hgt = np.asarray(mask.filter(ImageFilter.GaussianBlur(ss * 5)), dtype=np.float64) / 255
        # выдавленный оттиск: кольцо и звезда
        stamp = Image.new("L", (S, S), 0)
        sd = ImageDraw.Draw(stamp)
        sd.ellipse([cx - S * 0.27, cy - S * 0.27, cx + S * 0.27, cy + S * 0.27], outline=255, width=int(ss * 2.2))
        sd.polygon(star_points(cx, cy, S * 0.2, S * 0.1), fill=255)
        st = np.asarray(stamp.filter(ImageFilter.GaussianBlur(ss * 0.8)), dtype=np.float64) / 255
        hgt = hgt - 0.35 * st
        gy, gx = np.gradient(hgt)
        light = np.clip(0.5 - (gx + gy) * 18, 0, 1)
        c_mid, c_dark, c_hi = (np.array(rgb8(c), float) for c in (mid, dark, hi))
        col = c_dark + (c_mid - c_dark) * np.clip(light * 1.6, 0, 1)[..., None]
        col = col + (c_hi - c_mid) * np.clip((light - 0.62) * 2.5, 0, 1)[..., None]
        rgba = np.dstack([col, m * 255])
        img = from_arr(rgba, "RGBA").resize((s, s), Image.LANCZOS)
        save(img, f"seal_{name}.png")


def gen_cursors() -> None:
    """Курсор — наконечник стрелы (остриё в левом верхнем углу, точка 2,2) + значки контекста. 48×48."""
    s, ss = 48, 6
    S = s * ss

    def arrowhead(tint=None, grey=False) -> Image.Image:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img, "RGBA")
        tip = (2 * ss, 2 * ss)
        # лист наконечника вдоль диагонали
        L = 30 * ss
        ax = (tip[0] + L * 0.70, tip[1] + L * 0.70)
        blade = [tip, (tip[0] + 15 * ss, tip[1] + 6 * ss), (ax[0] - 2 * ss, ax[1] - 3 * ss), (ax[0] - 3 * ss, ax[1] - 2 * ss),
                 (tip[0] + 6 * ss, tip[1] + 15 * ss)]
        shadow = [(x + 2 * ss, y + 2.5 * ss) for x, y in blade]
        d.polygon(shadow, fill=(10, 5, 2, 110))
        # древко
        d.line([(ax[0] - 3 * ss, ax[1] - 3 * ss), (ax[0] + 9 * ss, ax[1] + 9 * ss)], fill=(20, 12, 6, 255), width=int(5 * ss))
        d.line([(ax[0] - 3 * ss, ax[1] - 3 * ss), (ax[0] + 9 * ss, ax[1] + 9 * ss)], fill=rgb8("#8a5a32") + (255,), width=int(3 * ss))
        # обмотка
        d.line([(ax[0] - 4 * ss, ax[1] - 1 * ss), (ax[0] - 1 * ss, ax[1] - 4 * ss)], fill=rgb8("#c8a060") + (255,), width=int(2 * ss))
        d.polygon(blade, fill=(24, 14, 6, 255))
        inner = [(tip[0] + 1.6 * ss, tip[1] + 1.6 * ss), (tip[0] + 13.5 * ss, tip[1] + 6.4 * ss), (ax[0] - 3 * ss, ax[1] - 3.6 * ss),
                 (tip[0] + 6.4 * ss, tip[1] + 13.5 * ss)]
        metal = (BRASS["hi"], BRASS["mid"]) if tint is None else tint
        if grey:
            metal = ("#c8c4bc", "#7a776f")
        d.polygon(inner, fill=rgb8(metal[1]) + (255,))
        # светлая грань (ребро наконечника)
        d.polygon([(tip[0] + 1.6 * ss, tip[1] + 1.6 * ss), (tip[0] + 13.5 * ss, tip[1] + 6.4 * ss), (ax[0] - 3 * ss, ax[1] - 3.6 * ss)],
                  fill=rgb8(metal[0]) + (255,))
        d.line([(tip[0] + 2 * ss, tip[1] + 2 * ss), (ax[0] - 3.5 * ss, ax[1] - 3.5 * ss)], fill=(40, 22, 8, 200), width=int(1 * ss))
        return img

    def badge(img: Image.Image, glyph) -> Image.Image:
        d = ImageDraw.Draw(img, "RGBA")
        cx, cy, r = 34 * ss, 34 * ss, 12 * ss
        d.ellipse([cx - r - ss, cy - r - ss, cx + r + ss, cy + r + ss], fill=(20, 12, 6, 230))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb8("#e9d9b4") + (255,))
        m = Image.new("L", (S, S), 0)
        glyph(ImageDraw.Draw(m), cx, cy, r * 0.8)
        ink = Image.new("RGBA", (S, S), rgb8(INK) + (255,))
        img.paste(ink, (0, 0), m)
        return img

    out = {
        "cursor": arrowhead(),
        "cursor_attack": arrowhead(tint=("#ff8a6a", "#a3281c")),
        "cursor_gather": badge(arrowhead(), lambda d, cx, cy, r: g_axe(d, cx, cy, r)),
        "cursor_build": badge(arrowhead(), lambda d, cx, cy, r: g_hammer(d, cx, cy, r)),
        "cursor_forbid": badge(arrowhead(grey=True), lambda d, cx, cy, r: g_cross(d, cx, cy, r)),
        "cursor_move": badge(arrowhead(), lambda d, cx, cy, r: g_flag(d, cx, cy, r)),
    }
    for name, img in out.items():
        save(img.resize((s, s), Image.LANCZOS), f"{name}.png")


# ================================================================= значки: маски-глифы

def thick(d, pts, w, fill=255):
    d.line(pts, fill=fill, width=int(w), joint="curve")
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def circ(d, cx, cy, r, fill=255, outline=None, width=0):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=int(width))


def arc_pts(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(a0 + (a1 - a0) * t / n), cy + r * math.sin(a0 + (a1 - a0) * t / n)) for t in range(n + 1)]


def g_axe(d, cx, cy, r):
    thick(d, [(cx - r * 0.7, cy + r * 0.8), (cx + r * 0.45, cy - r * 0.6)], r * 0.22)
    d.polygon([(cx + r * 0.15, cy - r * 0.95), (cx + r * 0.95, cy - r * 0.55), (cx + r * 0.75, cy + r * 0.1),
               (cx + r * 0.38, cy - r * 0.25)], fill=255)


def g_hammer(d, cx, cy, r):
    thick(d, [(cx - r * 0.75, cy + r * 0.8), (cx + r * 0.25, cy - r * 0.2)], r * 0.22)
    d.polygon([(cx - r * 0.05, cy - r * 0.95), (cx + r * 0.95, cy + r * 0.05), (cx + r * 0.6, cy + r * 0.4),
               (cx - r * 0.4, cy - r * 0.6)], fill=255)


def g_cross(d, cx, cy, r):
    thick(d, [(cx - r * 0.6, cy - r * 0.6), (cx + r * 0.6, cy + r * 0.6)], r * 0.32)
    thick(d, [(cx + r * 0.6, cy - r * 0.6), (cx - r * 0.6, cy + r * 0.6)], r * 0.32)


def g_flag(d, cx, cy, r):
    thick(d, [(cx - r * 0.55, cy + r * 0.95), (cx - r * 0.55, cy - r * 0.95)], r * 0.16)
    pts = [(cx - r * 0.5, cy - r * 0.95)]
    for k in range(9):
        t = k / 8
        pts.append((cx - r * 0.5 + t * r * 1.45, cy - r * 0.9 + t * r * 0.35 + math.sin(t * 6.3) * r * 0.1))
    pts += [(cx + r * 0.95, cy - r * 0.2), (cx - r * 0.5, cy + r * 0.05)]
    d.polygon(pts, fill=255)


def g_pennant(d, cx, cy, r):
    thick(d, [(cx - r * 0.5, cy + r * 0.95), (cx - r * 0.5, cy - r * 0.95)], r * 0.14)
    d.polygon([(cx - r * 0.45, cy - r * 0.95), (cx + r * 0.95, cy - r * 0.62), (cx + r * 0.55, cy - r * 0.5),
               (cx + r * 0.9, cy - r * 0.35), (cx - r * 0.45, cy - r * 0.15)], fill=255)
    # трезубец на древке
    thick(d, [(cx - r * 0.72, cy - r * 0.98), (cx - r * 0.72, cy - r * 0.78)], r * 0.08)


def g_bread(d, cx, cy, r):
    """Нон — лепёшка с узором в середине."""
    circ(d, cx, cy, r * 0.92)
    circ(d, cx, cy, r * 0.55, fill=0)
    circ(d, cx, cy, r * 0.47)
    for k in range(8):
        a = k * math.pi / 4
        circ(d, cx + r * 0.25 * math.cos(a), cy + r * 0.25 * math.sin(a), r * 0.05, fill=0)
    circ(d, cx, cy, r * 0.06, fill=0)


def g_logs(d, cx, cy, r):
    for (x, y) in [(-0.42, 0.32), (0.42, 0.32), (0.0, -0.36)]:
        circ(d, cx + x * r, cy + y * r, r * 0.42)
        circ(d, cx + x * r, cy + y * r, r * 0.27, fill=0)
        circ(d, cx + x * r, cy + y * r, r * 0.2)
        circ(d, cx + x * r, cy + y * r, r * 0.07, fill=0)


def g_stone(d, cx, cy, r):
    d.polygon([(cx - r * 0.95, cy + r * 0.75), (cx - r * 0.75, cy - r * 0.05), (cx - r * 0.1, cy - r * 0.2),
               (cx + r * 0.1, cy + r * 0.75)], fill=255)
    d.polygon([(cx + r * 0.05, cy + r * 0.75), (cx + r * 0.1, cy - r * 0.05), (cx + r * 0.85, cy - r * 0.15),
               (cx + r * 0.95, cy + r * 0.75)], fill=255)
    d.polygon([(cx - r * 0.55, cy - r * 0.15), (cx - r * 0.3, cy - r * 0.85), (cx + r * 0.45, cy - r * 0.9),
               (cx + r * 0.6, cy - r * 0.2)], fill=255)
    d.line([(cx - r * 0.95, cy + r * 0.75), (cx + r * 0.95, cy + r * 0.75)], fill=0, width=int(r * 0.05))
    d.line([(cx - r * 0.55, cy - r * 0.15), (cx + r * 0.6, cy - r * 0.2)], fill=0, width=int(r * 0.08))
    d.line([(cx + r * 0.08, cy - r * 0.15), (cx + r * 0.08, cy + r * 0.75)], fill=0, width=int(r * 0.08))


def g_coins(d, cx, cy, r):
    for k, (x, y) in enumerate([(-0.35, 0.45), (0.3, 0.5), (-0.05, 0.12)]):
        d.ellipse([cx + (x - 0.5) * r, cy + (y - 0.22) * r, cx + (x + 0.5) * r, cy + (y + 0.22) * r], fill=255)
        d.ellipse([cx + (x - 0.5) * r, cy + (y - 0.22) * r, cx + (x + 0.5) * r, cy + (y + 0.22) * r], outline=0,
                  width=int(r * 0.05))
    circ(d, cx + r * 0.2, cy - r * 0.35, r * 0.55)
    circ(d, cx + r * 0.2, cy - r * 0.35, r * 0.42, fill=0)
    circ(d, cx + r * 0.2, cy - r * 0.35, r * 0.36)
    d.rectangle([cx + r * 0.1, cy - r * 0.45, cx + r * 0.3, cy - r * 0.25], fill=0)


def g_clay(d, cx, cy, r):
    d.ellipse([cx - r * 0.75, cy - r * 0.45, cx + r * 0.75, cy + r * 0.9], fill=255)
    d.rectangle([cx - r * 0.3, cy - r * 0.8, cx + r * 0.3, cy - r * 0.3], fill=255)
    d.ellipse([cx - r * 0.45, cy - r * 0.95, cx + r * 0.45, cy - r * 0.68], fill=255)
    d.arc([cx - r * 0.55, cy - r * 0.1, cx + r * 0.55, cy + r * 0.4], 20, 160, fill=0, width=int(r * 0.08))


def g_bricks(d, cx, cy, r):
    w, h = r * 0.9, r * 0.42
    for row, (y, offs) in enumerate([(0.5, [-0.48, 0.48]), (0.02, [0.0]), (-0.46, [-0.3])]):
        for x in offs:
            x0 = cx + x * r - w / 2
            y0 = cy + y * r - h / 2
            d.rectangle([x0, y0, x0 + w, y0 + h], fill=255)
            d.rectangle([x0, y0, x0 + w, y0 + h], outline=0, width=int(r * 0.06))


def g_horse(d, cx, cy, r):
    """Голова коня в профиль (влево), с гривой."""
    pts = [(-0.05, -0.95), (0.18, -0.7), (0.5, -0.45), (0.75, 0.1), (0.8, 0.7), (0.3, 0.95), (0.18, 0.55),
           (-0.15, 0.35), (-0.55, 0.45), (-0.85, 0.32), (-0.92, 0.1), (-0.6, -0.25), (-0.3, -0.6), (-0.2, -0.95)]
    d.polygon([(cx + x * r, cy + y * r) for x, y in pts], fill=255)
    circ(d, cx - r * 0.25, cy - r * 0.3, r * 0.08, fill=0)
    circ(d, cx - r * 0.78, cy + r * 0.2, r * 0.05, fill=0)
    for k in range(4):
        y = -0.6 + k * 0.32
        thick(d, [(cx + r * (0.32 + k * 0.1), cy + r * y), (cx + r * (0.55 + k * 0.1), cy + r * (y + 0.12))], r * 0.07, fill=0)


def g_wool(d, cx, cy, r):
    for x, y, rr in [(-0.4, 0.2, 0.42), (0.35, 0.25, 0.45), (0.0, -0.3, 0.48), (-0.05, 0.45, 0.4)]:
        circ(d, cx + x * r, cy + y * r, rr * r)
    for x, y in [(-0.35, 0.15), (0.3, 0.2), (0.0, -0.3)]:
        d.arc([cx + (x - 0.2) * r, cy + (y - 0.2) * r, cx + (x + 0.2) * r, cy + (y + 0.2) * r], 200, 340, fill=0,
              width=int(r * 0.07))


def g_felt(d, cx, cy, r):
    d.rectangle([cx - r * 0.7, cy - r * 0.45, cx + r * 0.5, cy + r * 0.45], fill=255)
    d.ellipse([cx + r * 0.2, cy - r * 0.45, cx + r * 0.85, cy + r * 0.45], fill=255)
    for rr in (0.25, 0.13):
        d.ellipse([cx + (0.525 - rr) * r, cy - rr * 1.4 * r, cx + (0.525 + rr) * r, cy + rr * 1.4 * r], outline=0,
                  width=int(r * 0.06))
    d.rectangle([cx - r * 0.35, cy - r * 0.45, cx - r * 0.2, cy + r * 0.45], fill=0)
    d.ellipse([cx - r * 0.95, cy - r * 0.45, cx - r * 0.45, cy + r * 0.45], fill=255)


def g_people(d, cx, cy, r):
    for x, s in [(-0.38, 0.85), (0.35, 1.0)]:
        circ(d, cx + x * r, cy - r * 0.38 * s, r * 0.25 * s)
        d.pieslice([cx + (x - 0.42 * s) * r, cy - r * 0.05, cx + (x + 0.42 * s) * r, cy + r * 0.85 * s + r * 0.4],
                   180, 360, fill=255)
    d.line([(cx - r, cy + r * 0.62), (cx + r, cy + r * 0.62)], fill=0, width=int(r * 0.08))


def g_horn(d, cx, cy, r):
    """Карнай/рог: длинный раструб."""
    d.polygon([(cx - r * 0.95, cy + r * 0.25), (cx + r * 0.55, cy - r * 0.45), (cx + r * 0.75, cy - r * 0.95),
               (cx + r * 0.95, cy - r * 0.05), (cx + r * 0.7, cy - r * 0.15), (cx - r * 0.9, cy + r * 0.42)], fill=255)
    for t in (0.25, 0.55):
        x = cx - r * 0.95 + t * r * 1.5
        y = cy + r * 0.3 - t * r * 0.7
        thick(d, [(x, y - r * 0.12), (x + r * 0.06, y + r * 0.12)], r * 0.06, fill=0)


def g_sabers(d, cx, cy, r):
    for s in (-1, 1):
        pts = []
        for k in range(12):
            t = k / 11
            x = cx + s * (-0.85 + 1.6 * t) * r
            y = cy + (0.85 - 1.6 * t) * r - math.sin(t * math.pi) * r * 0.25 * s * s
            pts.append((x, y))
        thick(d, pts, r * 0.13)
        hx, hy = cx + s * -0.62 * r, cy + 0.62 * r
        thick(d, [(hx - r * 0.18, hy - r * 0.18 * s * s), (hx + r * 0.18, hy + r * 0.18)], r * 0.1)


def g_saber(d, cx, cy, r):
    pts = []
    for k in range(12):
        t = k / 11
        pts.append((cx + (-0.7 + 1.5 * t) * r, cy + (0.7 - 1.5 * t) * r - math.sin(t * math.pi) * r * 0.3))
    thick(d, pts, r * 0.16)
    thick(d, [(cx - r * 0.75, cy + r * 0.35), (cx - r * 0.35, cy + r * 0.75)], r * 0.12)


def g_hand(d, cx, cy, r):
    d.rounded_rectangle([cx - r * 0.5, cy - r * 0.15, cx + r * 0.45, cy + r * 0.85], radius=r * 0.2, fill=255)
    for k, (x, h) in enumerate([(-0.4, 0.55), (-0.15, 0.75), (0.1, 0.7), (0.34, 0.5)]):
        d.rounded_rectangle([cx + (x - 0.1) * r, cy - h * r, cx + (x + 0.1) * r, cy + r * 0.1], radius=r * 0.1, fill=255)
    d.polygon([(cx - r * 0.5, cy + r * 0.35), (cx - r * 0.95, cy - r * 0.05), (cx - r * 0.8, cy - r * 0.2),
               (cx - r * 0.45, cy + r * 0.05)], fill=255)


def g_grid(d, cx, cy, r):
    for i in range(3):
        for j in range(3):
            d.rectangle([cx + (i - 1) * r * 0.62 - r * 0.18, cy + (j - 1) * r * 0.62 - r * 0.18,
                         cx + (i - 1) * r * 0.62 + r * 0.18, cy + (j - 1) * r * 0.62 + r * 0.18], fill=255)


def g_shield(d, cx, cy, r):
    circ(d, cx, cy, r * 0.88)
    circ(d, cx, cy, r * 0.68, fill=0)
    circ(d, cx, cy, r * 0.6)
    circ(d, cx, cy, r * 0.2, fill=0)
    circ(d, cx, cy, r * 0.13)
    for k in range(6):
        a = k * math.pi / 3
        circ(d, cx + r * 0.78 * math.cos(a), cy + r * 0.78 * math.sin(a), r * 0.05, fill=0)


def g_bow(d, cx, cy, r, arrow_back=False):
    d.arc([cx - r * 1.3, cy - r * 0.95, cx + r * 0.3, cy + r * 0.95], -70, 70, fill=255, width=int(r * 0.16))
    tx = cx + r * 0.3 - r * 0.8 * (1 - math.cos(math.radians(70)))
    d.line([(cx - r * 0.25, cy - r * 0.88), (cx - r * 0.25, cy + r * 0.88)], fill=255, width=int(r * 0.05))
    if arrow_back:
        thick(d, [(cx + r * 0.95, cy), (cx - r * 0.55, cy)], r * 0.08)
        d.polygon([(cx - r * 0.95, cy), (cx - r * 0.55, cy - r * 0.18), (cx - r * 0.55, cy + r * 0.18)], fill=255)
    else:
        thick(d, [(cx - r * 0.25, cy), (cx + r * 0.6, cy)], r * 0.08)
        d.polygon([(cx + r * 0.95, cy), (cx + r * 0.6, cy - r * 0.18), (cx + r * 0.6, cy + r * 0.18)], fill=255)


def g_kachyp(d, cx, cy, r):
    g_bow(d, cx + r * 0.15, cy - r * 0.1, r * 0.8, arrow_back=True)
    d.arc([cx - r * 0.9, cy + r * 0.1, cx + r * 0.9, cy + r * 1.3], 200, 340, fill=255, width=int(r * 0.1))
    d.polygon([(cx + r * 0.95, cy + r * 0.45), (cx + r * 0.6, cy + r * 0.38), (cx + r * 0.85, cy + r * 0.72)], fill=255)


def g_fire_mode(d, cx, cy, r):
    g_bow(d, cx - r * 0.25, cy, r * 0.7)
    thick(d, [(cx + r * 0.05, cy + r * 0.9), (cx + r * 0.9, cy - r * 0.9)], r * 0.12)
    thick(d, [(cx + r * 0.08, cy + r * 0.55), (cx + r * 0.45, cy + r * 0.72)], r * 0.1)


def g_banner(d, cx, cy, r):
    thick(d, [(cx - r * 0.5, cy + r * 0.95), (cx - r * 0.5, cy - r * 0.9)], r * 0.12)
    d.polygon([(cx - r * 0.7, cy - r * 0.95), (cx - r * 0.5, cy - r * 1.0), (cx - r * 0.3, cy - r * 0.95),
               (cx - r * 0.5, cy - r * 0.75)], fill=255)
    d.polygon([(cx - r * 0.45, cy - r * 0.75), (cx + r * 0.85, cy - r * 0.75), (cx + r * 0.55, cy - r * 0.35),
               (cx + r * 0.85, cy + r * 0.05), (cx - r * 0.45, cy + r * 0.05)], fill=255)
    g_star_small(d, cx + r * 0.15, cy - r * 0.35, r * 0.2, fill=0)


def g_star_small(d, cx, cy, r, fill=255):
    d.polygon(star_points(cx, cy, r, r * 0.5), fill=fill)


def g_disband(d, cx, cy, r):
    g_banner(d, cx - r * 0.1, cy, r * 0.85)
    for k in range(3):
        a = -0.6 + k * 0.6
        x0, y0 = cx + r * 0.55, cy + r * 0.55
        thick(d, [(x0, y0), (x0 + r * 0.42 * math.cos(a), y0 + r * 0.42 * math.sin(a))], r * 0.08)


def g_pick(d, cx, cy, r):
    thick(d, [(cx - r * 0.65, cy + r * 0.85), (cx + r * 0.3, cy - r * 0.35)], r * 0.16)
    d.arc([cx - r * 0.55, cy - r * 1.15, cx + r * 1.15, cy + r * 0.55], 190, 340, fill=255, width=int(r * 0.2))


def g_assist(d, cx, cy, r):
    g_hammer(d, cx - r * 0.2, cy + r * 0.15, r * 0.8)
    thick(d, [(cx + r * 0.62, cy - r * 0.95), (cx + r * 0.62, cy - r * 0.35)], r * 0.16)
    thick(d, [(cx + r * 0.32, cy - r * 0.65), (cx + r * 0.92, cy - r * 0.65)], r * 0.16)


def g_yurt(d, cx, cy, r):
    d.rectangle([cx - r * 0.85, cy - r * 0.05, cx + r * 0.85, cy + r * 0.75], fill=255)
    d.chord([cx - r * 0.95, cy - r * 0.95, cx + r * 0.95, cy + r * 0.85], 180, 360, fill=255)
    d.rectangle([cx - r * 0.2, cy + r * 0.2, cx + r * 0.2, cy + r * 0.75], fill=0)
    d.line([(cx - r * 0.85, cy + r * 0.1), (cx + r * 0.85, cy + r * 0.1)], fill=0, width=int(r * 0.06))
    d.rectangle([cx - r * 0.18, cy - r * 0.62, cx + r * 0.18, cy - r * 0.52], fill=0)


def g_wheel(d, cx, cy, r):
    circ(d, cx, cy, r * 0.9)
    circ(d, cx, cy, r * 0.72, fill=0)
    circ(d, cx, cy, r * 0.2)
    for k in range(8):
        a = k * math.pi / 4
        thick(d, [(cx, cy), (cx + r * 0.75 * math.cos(a), cy + r * 0.75 * math.sin(a))], r * 0.1)


def g_pack_all(d, cx, cy, r):
    g_yurt(d, cx - r * 0.25, cy - r * 0.25, r * 0.65)
    g_wheel(d, cx + r * 0.45, cy + r * 0.45, r * 0.5)


def g_flame(d, cx, cy, r):
    d.chord([cx - r * 0.9, cy - r * 0.1, cx + r * 0.9, cy + r * 1.3], 180, 360, fill=255)
    d.rectangle([cx - r * 0.9, cy + r * 0.6, cx + r * 0.9, cy + r * 0.9], fill=255)
    d.polygon([(cx, cy - r * 0.95), (cx + r * 0.35, cy - r * 0.35), (cx + r * 0.1, cy - r * 0.05), (cx - r * 0.3, cy - r * 0.15),
               (cx - r * 0.25, cy - r * 0.55)], fill=255)
    d.ellipse([cx - r * 0.3, cy + r * 0.25, cx + r * 0.3, cy + r * 0.75], fill=0)


def g_broken_wall(d, cx, cy, r):
    g_bricks(d, cx, cy + r * 0.1, r * 0.95)
    d.polygon([(cx + r * 0.05, cy - r * 1.0), (cx - r * 0.15, cy - r * 0.2), (cx + r * 0.15, cy + r * 0.05),
               (cx - r * 0.1, cy + r * 1.0), (cx + r * 0.3, cy + r * 0.05), (cx, cy - r * 0.2)], fill=0)


def g_tower(d, cx, cy, r):
    d.polygon([(cx - r * 0.55, cy + r * 0.95), (cx - r * 0.42, cy - r * 0.5), (cx + r * 0.42, cy - r * 0.5),
               (cx + r * 0.55, cy + r * 0.95)], fill=255)
    for k in range(3):
        x = cx - r * 0.55 + k * r * 0.45
        d.rectangle([x, cy - r * 0.95, x + r * 0.25, cy - r * 0.45], fill=255)
    d.rectangle([cx - r * 0.65, cy - r * 0.62, cx + r * 0.65, cy - r * 0.45], fill=255)
    d.chord([cx - r * 0.2, cy + r * 0.45, cx + r * 0.2, cy + r * 0.85], 180, 360, fill=0)
    d.rectangle([cx - r * 0.2, cy + r * 0.65, cx + r * 0.2, cy + r * 0.95], fill=0)
    d.rectangle([cx - r * 0.06, cy - r * 0.2, cx + r * 0.06, cy + r * 0.1], fill=0)


def g_house(d, cx, cy, r):
    """Кокандский дом: плоская крыша, айван на столбах."""
    d.rectangle([cx - r * 0.9, cy - r * 0.45, cx + r * 0.9, cy + r * 0.8], fill=255)
    d.rectangle([cx - r * 1.0, cy - r * 0.62, cx + r * 1.0, cy - r * 0.42], fill=255)
    for x in (-0.55, 0.0, 0.55):
        d.rectangle([cx + (x - 0.16) * r, cy - r * 0.2, cx + (x + 0.16) * r, cy + r * 0.8], fill=0)
        d.rectangle([cx + (x - 0.05) * r, cy - r * 0.2, cx + (x + 0.05) * r, cy + r * 0.8], fill=255)
    d.line([(cx - r, cy - r * 0.5), (cx + r, cy - r * 0.5)], fill=0, width=int(r * 0.05))


def g_field(d, cx, cy, r):
    d.polygon([(cx - r * 0.95, cy + r * 0.85), (cx - r * 0.5, cy - r * 0.55), (cx + r * 0.5, cy - r * 0.55),
               (cx + r * 0.95, cy + r * 0.85)], fill=255)
    for k in range(5):
        t = (k + 0.5) / 5
        d.line([(cx - r * 0.5 + t * r * 1.0, cy - r * 0.55), (cx - r * 0.95 + t * r * 1.9, cy + r * 0.85)], fill=0,
               width=int(r * 0.07))
    for k in range(3):
        x = cx + (k - 1) * r * 0.45
        thick(d, [(x, cy - r * 0.6), (x, cy - r * 0.95)], r * 0.07)
        d.ellipse([x - r * 0.08, cy - r * 1.0, x + r * 0.08, cy - r * 0.75], fill=255)


def g_mill(d, cx, cy, r):
    circ(d, cx - r * 0.25, cy + r * 0.1, r * 0.75)
    circ(d, cx - r * 0.25, cy + r * 0.1, r * 0.55, fill=0)
    circ(d, cx - r * 0.25, cy + r * 0.1, r * 0.15)
    for k in range(8):
        a = k * math.pi / 4
        thick(d, [(cx - r * 0.25, cy + r * 0.1), (cx - r * 0.25 + r * 0.7 * math.cos(a), cy + r * 0.1 + r * 0.7 * math.sin(a))], r * 0.08)
    d.rectangle([cx + r * 0.35, cy - r * 0.55, cx + r * 0.95, cy + r * 0.9], fill=255)
    for k in range(3):
        d.arc([cx - r * 1.0 + k * r * 0.5, cy + r * 0.75, cx - r * 0.5 + k * r * 0.5, cy + r * 1.05], 180, 360, fill=255,
              width=int(r * 0.07))


def g_store(d, cx, cy, r):
    """Склад: мешки и ящик."""
    for x, y, s in [(-0.45, 0.35, 0.5), (0.35, 0.4, 0.48), (-0.05, -0.3, 0.5)]:
        d.ellipse([cx + (x - s * 0.7) * r, cy + (y - s) * r, cx + (x + s * 0.7) * r, cy + (y + s * 0.9) * r], fill=255)
        thick(d, [(cx + (x - 0.12) * r, cy + (y - s * 0.95) * r), (cx + (x + 0.12) * r, cy + (y - s * 0.95) * r)], r * 0.1, fill=0)


def g_barracks(d, cx, cy, r):
    for s in (-1, 1):
        thick(d, [(cx - s * r * 0.85, cy + r * 0.9), (cx + s * r * 0.75, cy - r * 0.8)], r * 0.1)
        bx, by = cx + s * r * 0.75, cy - r * 0.8
        d.polygon([(bx + s * r * 0.15, by - r * 0.2), (bx - s * r * 0.15, by + r * 0.05), (bx + s * r * 0.0, by + r * 0.2)], fill=255)
    g_shield(d, cx, cy + r * 0.15, r * 0.48)


def g_horseshoe(d, cx, cy, r):
    d.arc([cx - r * 0.8, cy - r * 0.85, cx + r * 0.8, cy + r * 0.75], 160, 380, fill=255, width=int(r * 0.32))
    for k in range(6):
        a = math.radians(170 + k * 40)
        circ(d, cx + r * 0.64 * math.cos(a), cy - r * 0.05 + r * 0.64 * math.sin(a), r * 0.05, fill=0)


def g_cannon(d, cx, cy, r):
    d.polygon([(cx - r * 0.95, cy - r * 0.15), (cx + r * 0.75, cy - r * 0.55), (cx + r * 0.85, cy - r * 0.2),
               (cx - r * 0.85, cy + r * 0.2)], fill=255)
    circ(d, cx - r * 0.85, cy + r * 0.02, r * 0.2)
    circ(d, cx - r * 0.1, cy + r * 0.45, r * 0.42)
    circ(d, cx - r * 0.1, cy + r * 0.45, r * 0.3, fill=0)
    circ(d, cx - r * 0.1, cy + r * 0.45, r * 0.09)
    for k in range(3):
        circ(d, cx + r * (0.45 + k * 0.2), cy + r * 0.8, r * 0.12)


def g_bazaar(d, cx, cy, r):
    d.rectangle([cx - r * 0.85, cy - r * 0.1, cx + r * 0.85, cy + r * 0.9], fill=255)
    d.chord([cx - r * 0.55, cy - r * 0.95, cx + r * 0.55, cy + r * 0.15], 180, 360, fill=255)
    d.chord([cx - r * 0.35, cy + r * 0.1, cx + r * 0.35, cy + r * 0.8], 180, 360, fill=0)
    d.rectangle([cx - r * 0.35, cy + r * 0.45, cx + r * 0.35, cy + r * 0.9], fill=0)
    thick(d, [(cx, cy - r * 0.42), (cx, cy - r * 0.75)], r * 0.06, fill=255)


def g_dam(d, cx, cy, r):
    d.rectangle([cx - r * 0.9, cy - r * 0.6, cx + r * 0.9, cy - r * 0.05], fill=255)
    for x in (-0.6, -0.2, 0.2, 0.6):
        d.line([(cx + x * r, cy - r * 0.6), (cx + x * r, cy - r * 0.05)], fill=0, width=int(r * 0.06))
    for k in range(2):
        y = cy + r * (0.3 + k * 0.35)
        pts = [(cx - r * 0.95 + t * r * 0.1, y + math.sin(t * 0.9) * r * 0.1) for t in range(20)]
        thick(d, pts, r * 0.1)


def g_canal(d, cx, cy, r):
    for k in range(3):
        y = cy + r * (-0.55 + k * 0.55)
        pts = [(cx - r * 0.95 + t * r * 0.1, y + math.sin(t * 0.9 + k) * r * 0.12) for t in range(20)]
        thick(d, pts, r * 0.13)


def g_wall(d, cx, cy, r):
    d.rectangle([cx - r * 0.95, cy - r * 0.35, cx + r * 0.95, cy + r * 0.85], fill=255)
    for k in range(5):
        x = cx - r * 0.95 + k * r * 0.42
        d.chord([x, cy - r * 0.75, x + r * 0.26, cy - r * 0.2], 180, 360, fill=255)
        d.rectangle([x, cy - r * 0.5, x + r * 0.26, cy - r * 0.3], fill=255)
    for y in (0.0, 0.42):
        d.line([(cx - r * 0.95, cy + y * r), (cx + r * 0.95, cy + y * r)], fill=0, width=int(r * 0.05))


def g_palisade(d, cx, cy, r):
    for k in range(6):
        x = cx - r * 0.85 + k * r * 0.34
        d.polygon([(x - r * 0.13, cy + r * 0.9), (x - r * 0.13, cy - r * 0.55), (x, cy - r * 0.9), (x + r * 0.13, cy - r * 0.55),
                   (x + r * 0.13, cy + r * 0.9)], fill=255)
    d.line([(cx - r, cy - r * 0.2), (cx + r, cy - r * 0.2)], fill=0, width=int(r * 0.08))
    d.line([(cx - r, cy + r * 0.45), (cx + r, cy + r * 0.45)], fill=0, width=int(r * 0.08))


def g_gate(d, cx, cy, r):
    d.rectangle([cx - r * 0.95, cy - r * 0.6, cx + r * 0.95, cy + r * 0.9], fill=255)
    for k in range(4):
        x = cx - r * 0.95 + k * r * 0.56
        d.rectangle([x, cy - r * 0.9, x + r * 0.26, cy - r * 0.55], fill=255)
    d.chord([cx - r * 0.45, cy - r * 0.25, cx + r * 0.45, cy + r * 0.6], 180, 360, fill=0)
    d.rectangle([cx - r * 0.45, cy + r * 0.15, cx + r * 0.45, cy + r * 0.9], fill=0)
    d.line([(cx, cy - r * 0.2), (cx, cy + r * 0.9)], fill=255, width=int(r * 0.05))


def g_pen(d, cx, cy, r):
    for k in range(5):
        x = cx - r * 0.85 + k * r * 0.42
        thick(d, [(x, cy + r * 0.9), (x, cy + r * 0.15)], r * 0.1)
    thick(d, [(cx - r * 0.95, cy + r * 0.35), (cx + r * 0.95, cy + r * 0.35)], r * 0.08)
    thick(d, [(cx - r * 0.95, cy + r * 0.7), (cx + r * 0.95, cy + r * 0.7)], r * 0.08)
    d.ellipse([cx - r * 0.55, cy - r * 0.75, cx + r * 0.45, cy + r * 0.05], fill=255)
    circ(d, cx + r * 0.55, cy - r * 0.5, r * 0.22)
    d.arc([cx + r * 0.42, cy - r * 0.75, cx + r * 0.95, cy - r * 0.25], 200, 330, fill=0, width=int(r * 0.07))


def g_horseyard(d, cx, cy, r):
    g_horse(d, cx + r * 0.05, cy - r * 0.3, r * 0.62)
    thick(d, [(cx - r * 0.95, cy + r * 0.55), (cx + r * 0.95, cy + r * 0.55)], r * 0.09)
    thick(d, [(cx - r * 0.95, cy + r * 0.85), (cx + r * 0.95, cy + r * 0.85)], r * 0.09)
    for x in (-0.8, 0.0, 0.8):
        thick(d, [(cx + x * r, cy + r * 0.35), (cx + x * r, cy + r * 0.98)], r * 0.1)


def g_mine(d, cx, cy, r):
    g_stone(d, cx - r * 0.15, cy + r * 0.3, r * 0.7)
    g_pick(d, cx + r * 0.35, cy - r * 0.3, r * 0.6)


def g_kurultai(d, cx, cy, r):
    g_yurt(d, cx - r * 0.1, cy + r * 0.15, r * 0.82)
    thick(d, [(cx + r * 0.8, cy + r * 0.95), (cx + r * 0.8, cy - r * 0.95)], r * 0.08)
    d.polygon([(cx + r * 0.68, cy - r * 0.95), (cx + r * 0.8, cy - r * 1.0), (cx + r * 0.92, cy - r * 0.95), (cx + r * 0.8, cy - r * 0.75)], fill=255)
    d.polygon([(cx + r * 0.82, cy - r * 0.72), (cx + r * 1.0, cy - r * 0.6), (cx + r * 0.82, cy - r * 0.42)], fill=255)


def g_anvil(d, cx, cy, r):
    d.polygon([(cx - r * 0.95, cy - r * 0.35), (cx + r * 0.85, cy - r * 0.35), (cx + r * 0.55, cy + r * 0.05),
               (cx + r * 0.25, cy + r * 0.05), (cx + r * 0.35, cy + r * 0.55), (cx + r * 0.6, cy + r * 0.85),
               (cx - r * 0.6, cy + r * 0.85), (cx - r * 0.35, cy + r * 0.55), (cx - r * 0.25, cy + r * 0.05),
               (cx - r * 0.55, cy + r * 0.05)], fill=255)
    g_hammer(d, cx + r * 0.1, cy - r * 0.8, r * 0.45)


def g_worker(d, cx, cy, r):
    """Кетмень: широкая мотыга."""
    thick(d, [(cx - r * 0.7, cy + r * 0.85), (cx + r * 0.45, cy - r * 0.55)], r * 0.13)
    d.polygon([(cx + r * 0.25, cy - r * 0.75), (cx + r * 0.95, cy - r * 0.25), (cx + r * 0.6, cy + r * 0.35),
               (cx + r * 0.3, cy - r * 0.35)], fill=255)


def g_sword_shield(d, cx, cy, r):
    thick(d, [(cx - r * 0.85, cy + r * 0.85), (cx + r * 0.75, cy - r * 0.75)], r * 0.13)
    thick(d, [(cx - r * 0.6, cy + r * 0.3), (cx - r * 0.3, cy + r * 0.6)], r * 0.11)
    circ(d, cx + r * 0.15, cy + r * 0.2, r * 0.58)
    circ(d, cx + r * 0.15, cy + r * 0.2, r * 0.45, fill=0)
    circ(d, cx + r * 0.15, cy + r * 0.2, r * 0.38)
    circ(d, cx + r * 0.15, cy + r * 0.2, r * 0.12, fill=0)


def g_musket(d, cx, cy, r):
    thick(d, [(cx - r * 0.95, cy + r * 0.35), (cx + r * 0.95, cy - r * 0.55)], r * 0.12)
    d.polygon([(cx - r * 0.95, cy + r * 0.25), (cx - r * 0.35, cy + r * 0.0), (cx - r * 0.3, cy + r * 0.25),
               (cx - r * 0.8, cy + r * 0.75)], fill=255)
    thick(d, [(cx - r * 0.25, cy + r * 0.05), (cx - r * 0.1, cy + r * 0.35)], r * 0.08)
    thick(d, [(cx + r * 0.95, cy - r * 0.55), (cx + r * 0.95, cy - r * 0.95)], r * 0.06)


def g_spear(d, cx, cy, r):
    thick(d, [(cx - r * 0.85, cy + r * 0.85), (cx + r * 0.55, cy - r * 0.55)], r * 0.1)
    d.polygon([(cx + r * 0.95, cy - r * 0.95), (cx + r * 0.42, cy - r * 0.68), (cx + r * 0.68, cy - r * 0.42)], fill=255)
    thick(d, [(cx + r * 0.32, cy - r * 0.55), (cx + r * 0.55, cy - r * 0.32)], r * 0.08)


def g_rider(d, cx, cy, r):
    g_horse(d, cx, cy + r * 0.1, r * 0.85)
    thick(d, [(cx - r * 0.95, cy + r * 0.95), (cx + r * 0.95, cy - r * 0.95)], r * 0.07, fill=255)


def g_general(d, cx, cy, r):
    """Туг — бунчук полководца: древко, трезубец, конские хвосты."""
    thick(d, [(cx, cy + r * 0.95), (cx, cy - r * 0.6)], r * 0.1)
    for x in (-0.25, 0.0, 0.25):
        thick(d, [(cx + x * r, cy - r * 0.6), (cx + x * r * 1.1, cy - r * 0.95)], r * 0.08)
    thick(d, [(cx - r * 0.25, cy - r * 0.6), (cx + r * 0.25, cy - r * 0.6)], r * 0.08)
    for k in range(5):
        a = math.radians(110 + k * 8)
        thick(d, [(cx, cy - r * 0.45), (cx + r * 0.7 * math.cos(a) * (1 if k % 2 else -1), cy - r * 0.45 + r * 0.75 * math.sin(a))], r * 0.1)


def g_arba(d, cx, cy, r):
    d.rectangle([cx - r * 0.95, cy - r * 0.45, cx + r * 0.35, cy + r * 0.05], fill=255)
    d.chord([cx - r * 0.85, cy - r * 0.95, cx + r * 0.25, cy - r * 0.1], 180, 360, fill=255)
    thick(d, [(cx + r * 0.35, cy - r * 0.15), (cx + r * 0.98, cy + r * 0.05)], r * 0.08)
    g_wheel(d, cx - r * 0.3, cy + r * 0.45, r * 0.5)


def g_rally(d, cx, cy, r):
    g_pennant(d, cx, cy, r)


def g_ungarrison(d, cx, cy, r):
    g_tower(d, cx - r * 0.2, cy, r * 0.8)
    d.polygon([(cx + r * 0.95, cy + r * 0.4), (cx + r * 0.5, cy + r * 0.05), (cx + r * 0.5, cy + r * 0.75)], fill=255)


def g_menu(d, cx, cy, r):
    for y in (-0.45, 0.0, 0.45):
        thick(d, [(cx - r * 0.6, cy + y * r), (cx + r * 0.6, cy + y * r)], r * 0.16)


def g_pause(d, cx, cy, r):
    d.rectangle([cx - r * 0.45, cy - r * 0.6, cx - r * 0.12, cy + r * 0.6], fill=255)
    d.rectangle([cx + r * 0.12, cy - r * 0.6, cx + r * 0.45, cy + r * 0.6], fill=255)


def g_play(d, cx, cy, r):
    d.polygon([(cx - r * 0.4, cy - r * 0.6), (cx + r * 0.6, cy), (cx - r * 0.4, cy + r * 0.6)], fill=255)


def g_hourglass(d, cx, cy, r):
    d.rectangle([cx - r * 0.6, cy - r * 0.85, cx + r * 0.6, cy - r * 0.7], fill=255)
    d.rectangle([cx - r * 0.6, cy + r * 0.7, cx + r * 0.6, cy + r * 0.85], fill=255)
    d.polygon([(cx - r * 0.45, cy - r * 0.7), (cx + r * 0.45, cy - r * 0.7), (cx + r * 0.08, cy), (cx + r * 0.45, cy + r * 0.7),
               (cx - r * 0.45, cy + r * 0.7), (cx - r * 0.08, cy)], fill=255)
    d.polygon([(cx - r * 0.25, cy - r * 0.55), (cx + r * 0.25, cy - r * 0.55), (cx, cy - r * 0.2)], fill=0)


def g_raid(d, cx, cy, r):
    """Набег: две стрелы крест-накрест."""
    for s in (-1, 1):
        thick(d, [(cx - s * r * 0.85, cy + r * 0.85), (cx + s * r * 0.6, cy - r * 0.6)], r * 0.09)
        tx, ty = cx + s * r * 0.85, cy - r * 0.85
        d.polygon([(tx, ty), (tx - s * r * 0.4, ty + r * 0.12), (tx - s * r * 0.12, ty + r * 0.4)], fill=255)
        fx, fy = cx - s * r * 0.75, cy + r * 0.75
        d.polygon([(fx, fy), (fx - s * r * 0.25, fy - r * 0.05), (fx + s * r * 0.05, fy - r * 0.05)], fill=255)


def g_season(d, cx, cy, r):
    circ(d, cx, cy, r * 0.42)
    for k in range(8):
        a = k * math.pi / 4
        thick(d, [(cx + r * 0.58 * math.cos(a), cy + r * 0.58 * math.sin(a)), (cx + r * 0.88 * math.cos(a), cy + r * 0.88 * math.sin(a))], r * 0.1)


def g_star8(d, cx, cy, r):
    d.polygon(star_points(cx, cy, r * 0.95, r * 0.55), fill=255)
    circ(d, cx, cy, r * 0.3, fill=0)
    circ(d, cx, cy, r * 0.18)


def g_ramhorn_crest(d, cx, cy, r):
    for s in (-1, 1):
        pts = []
        for k in range(30):
            t = k / 29
            a = -math.pi / 2 + s * t * 1.7 * math.pi
            rr = r * 0.5 * (1 - 0.7 * t)
            pts.append((cx + s * r * 0.45 + rr * math.cos(a) * s, cy - r * 0.05 + rr * math.sin(a)))
        thick(d, [(cx, cy + r * 0.85), (cx, cy - r * 0.2), (cx + s * r * 0.45, cy - r * 0.55)] + pts, r * 0.12)


def mask_of(glyph, S: int) -> Image.Image:
    m = Image.new("L", (S, S), 0)
    glyph(ImageDraw.Draw(m), S / 2, S / 2, S * 0.4)
    return m


def engrave(mask: Image.Image, top: str, bottom: str, out_size: int, outline: str = INK, shadow: bool = True,
            outline_w: float = 0.03) -> Image.Image:
    """Гравированный значок: заливка градиентом по маске, тёмный контур (и прорези), мягкая тень."""
    S = mask.size[0]
    m = np.asarray(mask, dtype=np.float64) / 255
    k = max(3, int(S * outline_w) | 1)
    dil = np.asarray(mask.filter(ImageFilter.MaxFilter(k)), dtype=np.float64) / 255
    t = np.linspace(0, 1, S)[:, None, None]
    a, b = np.array(rgb8(top), float), np.array(rgb8(bottom), float)
    fill = a * (1 - t) + b * t
    # блик вдоль верхней кромки формы
    up = np.roll(m, int(S * 0.02), axis=0)
    rim = np.clip(m - up, 0, 1)[..., None]
    fill = fill * (1 - 0.0) + np.array(rgb8("#fff4d6"), float) * 0.55 * rim + fill * -0.55 * rim
    ol = np.array(rgb8(outline), float)
    col = ol[None, None, :] * (1 - m[..., None]) + fill * m[..., None]
    alpha = dil
    rgba = np.dstack([col, alpha * 255])
    img = from_arr(rgba, "RGBA")
    if shadow:
        sh = Image.fromarray((dil * 150).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(S * 0.02))
        base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        dark = Image.new("RGBA", (S, S), (12, 6, 2, 255))
        dark.putalpha(sh)
        base.alpha_composite(dark, (int(S * 0.02), int(S * 0.03)))
        base.alpha_composite(img)
        img = base
    return img.resize((out_size, out_size), Image.LANCZOS)


def gen_icons() -> None:
    S = 256
    gilt = ("#fbecc4", "#c9994a")
    # ресурсы (цветные)
    res = {
        "food": (g_bread, ("#f0c070", "#a8682a")),
        "wood": (g_logs, ("#c08a58", "#6a4024")),
        "stone": (g_stone, ("#d4d0c4", "#7c786c")),
        "gold": (g_coins, ("#ffe28a", "#c08a1e")),
        "clay": (g_clay, ("#d49a6a", "#8a5030")),
        "brick": (g_bricks, ("#e08a5a", "#9a4424")),
        "horse": (g_horse, ("#c88a5a", "#6b3f26")),
        "wool": (g_wool, ("#f4ecd8", "#b8a888")),
        "felt": (g_felt, ("#f6eedc", "#c4b494")),
        "people": (g_people, ("#f0dcb0", "#b08850")),
        "raid": (g_raid, ("#ff9a7a", "#a8281c")),
        "season": (g_season, ("#ffe08a", "#d08a2a")),
    }
    for name, (g, (top, bot)) in res.items():
        save(engrave(mask_of(g, S), top, bot, 48), f"res_{name}.png", ICONS)
    # приказы (золочёная гравировка)
    orders = {
        "move": g_flag, "stop": g_hand, "attack": g_saber, "attack_move": g_sabers, "hold": g_shield,
        "formation": g_grid, "stance": g_shield, "kachyp": g_kachyp, "fire_mode": g_fire_mode, "war_cry": g_horn,
        "form_squad": g_banner, "disband": g_disband, "gather": g_pick, "build": g_hammer, "assist": g_assist,
        "unpack": g_yurt, "pack": g_wheel, "pack_all": g_pack_all, "rally": g_rally, "recipe": g_flame,
        "demolish": g_broken_wall, "garrison": g_tower, "ungarrison": g_ungarrison, "trade": g_coins,
        "set_dam": g_dam, "herd_move": g_pen, "menu": g_menu, "pause": g_pause, "play": g_play, "speed": g_hourglass,
    }
    for name, g in orders.items():
        save(engrave(mask_of(g, S), *gilt, 56), f"ord_{name}.png", ICONS)
    # роды войск (портреты-эмблемы до рендеров моделей)
    units = {"worker": g_worker, "infantry": g_sword_shield, "musket": g_musket, "archer": g_bow, "spear": g_spear,
             "cavalry": g_horse, "lancer": g_rider, "horse_archer": g_kachyp, "officer": g_banner, "general": g_general,
             "cannon": g_cannon, "arba": g_arba}
    for name, g in units.items():
        save(engrave(mask_of(g, S), "#fff2cc", "#d6aa58", 72), f"unit_{name}.png", ICONS)
    # постройки (кнопки меню стройки)
    blds = {"house": g_house, "yurt": g_yurt, "field": g_field, "mill": g_mill, "store": g_store,
            "barracks": g_barracks, "stable": g_horseshoe, "cannon_yard": g_cannon, "kiln": g_flame, "bazaar": g_bazaar,
            "dam": g_dam, "canal": g_canal, "wall": g_wall, "palisade": g_palisade, "gate": g_gate, "tower": g_tower,
            "pen": g_pen, "horse_yard": g_horseyard, "mine": g_mine, "kurultai": g_kurultai, "smithy": g_anvil,
            "felt_yard": g_felt, "hq_kokand": g_bazaar, "hq_kipchak": g_kurultai}
    for name, g in blds.items():
        save(engrave(mask_of(g, S), *gilt, 56), f"bld_{name}.png", ICONS)
    # гербы сторон (пустая панель)
    save(engrave(mask_of(g_star8, S), "#bff4e4", "#2a8a74", 128), "crest_kokand.png", ICONS)
    save(engrave(mask_of(g_ramhorn_crest, S), "#ffd0c4", "#a8322a", 128), "crest_kipchak.png", ICONS)


def contact_sheet(path: str) -> None:
    """Сводный лист всех картинок (для проверки глазами; в git не идёт)."""
    files = []
    for folder in (OUT, ICONS):
        for f in sorted(os.listdir(folder)):
            if f.endswith(".png"):
                files.append(os.path.join(folder, f))
    cell = 110
    cols = 14
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), (60, 52, 44))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        im.thumbnail((cell - 10, cell - 10))
        x, y = (i % cols) * cell + 5, (i // cols) * cell + 5
        sheet.paste(im, (x, y), im)
    sheet.save(path)


def main() -> None:
    os.makedirs(ICONS, exist_ok=True)
    gen_beam()
    gen_panel()
    gen_frames()
    gen_paper()
    gen_buttons()
    gen_tabs()
    gen_plaque()
    gen_note()
    gen_card()
    gen_belt_kokand()
    gen_belt_kipchak()
    gen_seals()
    gen_cursors()
    gen_icons()
    if len(sys.argv) > 1:
        contact_sheet(sys.argv[1])


if __name__ == "__main__":
    main()
