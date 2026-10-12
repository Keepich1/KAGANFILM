"""Рисованные бесшовные текстуры земли (ТЗ 11.1: видимые мазки, земля темнее и спокойнее юнитов).

    python3 tools/gen_world_tex.py

assets/textures/world/ground_*.png — 1024², RGBA: цвет + «высота» мазка в альфе
(по ней шейдер земли смешивает слои рисованной границей, а не размытой).
Одна плитка ≈ 7 м земли. Палитра — приглушённые охры, олива, серо-зелёный.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

from paint import Canvas, fbm, value_noise  # noqa: E402
from palette import GROUND  # noqa: E402

SIZE = 1024
OUT = os.path.join(ROOT, "assets/textures/world")


def _height_from(c: Canvas, base_noise, k_lum=0.6):
    """Высота мазка: светлые мазки «выше» + крупный шум."""
    im = np.asarray(c.image(), dtype=np.float64) / 255.0
    lum = im @ np.array([0.3, 0.55, 0.15])
    lum = (lum - lum.min()) / max(np.ptp(lum), 1e-6)
    h = k_lum * lum + (1 - k_lum) * base_noise
    return (h - h.min()) / max(np.ptp(h), 1e-6)


def _save(c: Canvas, height, name):
    rgb = c.image().convert("RGBA")
    a = Image.fromarray((np.clip(height, 0, 1) * 255).astype(np.uint8), "L")
    rgb.putalpha(a)
    os.makedirs(OUT, exist_ok=True)
    rgb.save(os.path.join(OUT, name), optimize=True)
    print("  ", name)


def tuft_strokes(c: Canvas, n, colors, size=(10, 22), width=(2.5, 5), alpha=(0.35, 0.8), density=None, seed=0):
    """Пучки травы сверху: короткие мазки веером из центра пучка."""
    rs = np.random.default_rng(seed)
    for _ in range(n):
        x, y = rs.uniform(0, c.w), rs.uniform(0, c.h)
        if density is not None and rs.random() > density[int(y) % density.shape[0], int(x) % density.shape[1]]:
            continue
        k = int(rs.integers(4, 9))
        base_a = rs.uniform(0, 360)
        L = rs.uniform(*size)
        for i in range(k):
            a = base_a + i * 360.0 / k + rs.normal(0, 18)
            ln = L * rs.uniform(0.6, 1.1)
            cx = x + math.cos(math.radians(a)) * ln * 0.45
            cy = y + math.sin(math.radians(a)) * ln * 0.45
            c.strokes(1, colors, length=(ln * 0.8, ln), width=width, angle=a, angle_jitter=6,
                      alpha=alpha, region=(cx, cy, cx + 0.01, cy + 0.01), bristles=2, taper=0.8, curve=0.3)


def grass():
    """Степная трава: олива и серо-зелёный, пучки, редкие сухие стебли."""
    c = Canvas(SIZE, SIZE, base=GROUND["olive_dark"], seed=11)
    c.underpaint(["#3d4430", GROUND["olive_dark"], "#4d5031", "#4b5239", "#545634"], cell=220, octaves=3)
    dens = fbm(SIZE, SIZE, 180, 3, seed=12)
    # тёмная подложка между пучками
    c.strokes(1500, ["#2f3524", "#3a3c26", "#35392a"], length=(16, 40), width=(8, 16), angle=lambda x, y: (x * 0.3 + y * 0.5) % 360,
              angle_jitter=60, alpha=(0.25, 0.5), bristles=2)
    tuft_strokes(c, 900, ["#4c5230", "#5b6038", "#4a573f", "#5f6a4a"], size=(16, 30), width=(3, 6),
                 alpha=(0.45, 0.85), seed=13)
    tuft_strokes(c, 700, ["#6c6f42", "#727a50", "#68704f", "#7a7448"], size=(10, 20), width=(2.5, 4.5),
                 alpha=(0.5, 0.9), density=dens, seed=14)
    # блики на кончиках — тёплые и холодные
    tuft_strokes(c, 380, ["#8a8556", "#7f8a63", "#958a5a"], size=(6, 12), width=(2, 3.5), alpha=(0.45, 0.8),
                 density=dens, seed=15)
    # сухие стебли охрой
    c.strokes(500, [GROUND["ochre"], "#7d6c45", "#8f7d52"], length=(14, 30), width=(1.5, 3), angle=lambda x, y: 20 + 60 * math.sin(x * 0.01),
              angle_jitter=70, alpha=(0.35, 0.7), bristles=1, curve=0.4)
    c.grain(0.035)
    h = _height_from(c, dens, 0.7)
    _save(c, h, "ground_grass.png")


def dry():
    """Сухая выгоревшая трава и земля: охра, солома, пыль."""
    c = Canvas(SIZE, SIZE, base=GROUND["ochre"], seed=21)
    c.underpaint(["#6e5d3b", GROUND["ochre"], "#7d6a44", GROUND["olive"], "#937d52"], cell=240, octaves=3)
    dens = fbm(SIZE, SIZE, 150, 3, seed=22)
    # земля в просветах
    c.strokes(900, ["#5a4a31", "#665338", "#4f4430"], length=(18, 44), width=(8, 18), angle=10, angle_jitter=40,
              alpha=(0.3, 0.6), bristles=3)
    # длинные полегшие стебли
    c.strokes(2600, ["#8d7a4f", "#9d8a5c", "#7c6b46", "#a8915e"], length=(18, 42), width=(2, 4),
              angle=lambda x, y: -25 + 30 * math.sin(y * 0.012 + x * 0.004), angle_jitter=22,
              alpha=(0.4, 0.85), bristles=2, curve=0.35, density_map=dens * 0.6 + 0.4)
    tuft_strokes(c, 420, ["#6a6438", "#77703f", "#5f5d36"], size=(10, 22), width=(2.5, 4), alpha=(0.4, 0.8),
                 density=1 - dens, seed=23)
    # светлые блики соломы
    c.strokes(900, ["#bba373", "#b39a6e", "#c4ab78"], length=(8, 20), width=(1.5, 3),
              angle=lambda x, y: -25 + 30 * math.sin(y * 0.012 + x * 0.004), angle_jitter=25,
              alpha=(0.35, 0.75), bristles=1, density_map=dens)
    c.grain(0.035)
    h = _height_from(c, dens, 0.6)
    _save(c, h, "ground_dry.png")


def earth():
    """Вытоптанная земля у лагеря и на тропах: бурая, с отпечатками копыт и соломой."""
    c = Canvas(SIZE, SIZE, base=GROUND["earth"], seed=31)
    c.underpaint(["#4a3a28", GROUND["earth"], "#6a543a", "#57472f", "#76603f"], cell=200, octaves=3)
    n = fbm(SIZE, SIZE, 120, 3, seed=32)
    # плоские растёртые мазки
    c.strokes(1800, ["#4d3d2a", "#5f4b33", "#6b563b", "#7a6444"], length=(24, 60), width=(10, 22), angle=5,
              angle_jitter=25, alpha=(0.25, 0.55), bristles=5, curve=0.15)
    # пыль светлыми растёртыми пятнами
    c.strokes(500, [GROUND["dust"], "#9c845c", "#a38b62"], length=(20, 50), width=(8, 18), angle=0, angle_jitter=30,
              alpha=(0.15, 0.35), bristles=6, density_map=n)
    # отпечатки копыт: тёмные полумесяцы с тёплым бликом на краю
    rs = np.random.default_rng(33)
    for _ in range(260):
        x, y = rs.uniform(0, SIZE, 2)
        r = rs.uniform(5, 9)
        a = rs.uniform(0, 2 * np.pi)
        pts = [(x + r * math.cos(a + t), y + r * 0.8 * math.sin(a + t)) for t in np.linspace(-1.9, 1.9, 9)]
        c.line(pts, rs.uniform(2.5, 4.0), "#33281c", alpha=rs.uniform(0.45, 0.75), wobble=0.4, seed=int(x * 7 + y))
        pts2 = [(px + 1.5 * math.cos(a), py + 1.5 * math.sin(a)) for px, py in pts[2:-2]]
        c.line(pts2, 1.5, "#8f7650", alpha=0.45, wobble=0.3, seed=int(x + y * 3))
    # камешки и солома
    for _ in range(420):
        x, y = rs.uniform(0, SIZE, 2)
        rr = rs.uniform(2, 5)
        c.ellipse(x, y, rr, rr * 0.75, "#3e3428", alpha=0.6)
        c.ellipse(x - rr * 0.25, y - rr * 0.3, rr * 0.6, rr * 0.45, rs.choice(["#8a7a62", "#7e7462", "#94806a"]), alpha=0.8)
    c.strokes(300, ["#8d7a4f", "#a08a5a"], length=(10, 24), width=(1.2, 2.2), angle=lambda x, y: x * 0.7, angle_jitter=90,
              alpha=(0.4, 0.75), bristles=1, curve=0.5)
    tuft_strokes(c, 140, ["#4c5230", "#575b35"], size=(8, 16), width=(2, 3.5), alpha=(0.4, 0.75), density=n, seed=34)
    c.grain(0.04)
    h = _height_from(c, n, 0.5)
    _save(c, h, "ground_earth.png")


def _facets(size, n, seed, squash=0.55, warp=26.0):
    """Бесшовные ячейки Вороного: номер ячейки и расстояние до границы (в пикселях).
    Координаты искривлены шумом — границы граней «от руки», а не по линейке."""
    rs = np.random.default_rng(seed)
    pts = rs.uniform(0, size, (n, 2))
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    xx = xx + warp * (fbm(size, size, 110, 3, seed=seed + 1) - 0.5).astype(np.float32) * 2
    yy = yy + warp * (fbm(size, size, 110, 3, seed=seed + 2) - 0.5).astype(np.float32) * 2
    d1 = np.full((size, size), np.inf, np.float32)
    d2 = np.full((size, size), np.inf, np.float32)
    idx = np.zeros((size, size), np.int32)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, size - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, size - dy) / squash          # плиты вытянуты по горизонтали (слоистость)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, k, idx)
        d1 = np.where(closer, d, d1)
    return idx, d2 - d1


def rock():
    """Скала: рисованные плоскости-грани (тёплый свет, холодная тень), трещины по границам, лишайник."""
    S = SIZE
    rs = np.random.default_rng(43)
    idx, edge = _facets(S, 64, 44)
    k = idx.max() + 1
    ang = rs.uniform(0, 2 * np.pi, k)                 # наклон грани
    lit = np.clip(0.5 + 0.5 * np.cos(ang - 2.3) + rs.normal(0, 0.12, k), 0, 1)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    grad = (np.cos(ang)[idx] * xx + np.sin(ang)[idx] * yy) * 2.0
    grad = grad - np.floor(grad)
    v = lit[idx] * 0.8 + 0.2 * (1 - np.abs(grad - 0.5) * 2) * 0.6
    warm = np.array([0.57, 0.52, 0.44])
    cool = np.array([0.30, 0.30, 0.33])
    mid = np.array([0.43, 0.41, 0.38])
    t = v[..., None]
    col = np.where(t > 0.5, mid + (warm - mid) * (t - 0.5) * 2, cool + (mid - cool) * t * 2)
    n = fbm(S, S, 140, 4, seed=45)
    col *= (0.88 + 0.24 * n)[..., None]
    # трещины: тёмная щель по границе ячеек, местами прерывается
    brk = fbm(S, S, 60, 2, seed=46)
    crack = (1 - np.clip(edge / 3.5, 0, 1)) * (brk > 0.35)
    col = col * (1 - 0.65 * crack[..., None]) + np.array([0.13, 0.13, 0.16]) * 0.65 * crack[..., None]
    # светлая кромка над трещиной
    rim = np.clip(1 - np.abs(edge - 5) / 2.5, 0, 1) * (brk > 0.35) * (lit[idx] > 0.45)
    col = col + rim[..., None] * 0.12 * np.array([1.0, 0.92, 0.78])
    c = Canvas(S, S, base=GROUND["rock"], seed=41)
    big = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).resize((S * c.ss, S * c.ss), Image.BICUBIC)
    c._blend(np.asarray(big, dtype=np.float64))
    c.soften(0.6)

    # мазки вдоль граней: цвет ближе к цвету грани
    def along(x, y):
        return math.degrees(ang[idx[int(y) % S, int(x) % S]]) + 90

    c.strokes(900, ["#8a8172", "#6f6a5e", "#5a5852", "#9a8d74", "#4d4b4f"], length=(30, 80), width=(8, 18),
              angle=along, angle_jitter=10, alpha=(0.1, 0.3), bristles=6, curve=0.08, taper=0.4)
    # лишайник охрой и оливой
    c.strokes(240, ["#8a7448", "#76703e", "#9a8550"], length=(5, 12), width=(4, 9), angle=0, angle_jitter=180,
              alpha=(0.25, 0.5), bristles=2, density_map=n ** 2)
    c.grain(0.035)
    h = np.clip(lit[idx] * 0.6 + 0.4 * n - crack * 0.5, 0, 1)
    _save(c, h, "ground_rock.png")


def sand():
    """Песок и галька у реки: светлая охра, окатыши с нарисованным светом."""
    c = Canvas(SIZE, SIZE, base=GROUND["dust"], seed=51)
    c.underpaint(["#7a6a4e", "#8f7d5c", GROUND["dust"], "#857a66", "#9e8a66"], cell=220, octaves=3)
    n = fbm(SIZE, SIZE, 140, 3, seed=52)
    c.strokes(900, ["#a8915e", "#b39a6e", "#8f7d5c", "#7d7062"], length=(20, 50), width=(8, 18), angle=0,
              angle_jitter=12, alpha=(0.2, 0.45), bristles=6, curve=0.1)
    rs = np.random.default_rng(53)
    pal = ["#6f6a62", "#7d756a", "#8c7f6c", "#5c5a58", "#9a8a72", "#6a6258"]
    for _ in range(2600):
        x, y = rs.uniform(0, SIZE, 2)
        if rs.random() > 0.25 + 0.75 * n[int(y), int(x)]:
            continue
        r = rs.uniform(2.0, 6.5) * (1.5 if rs.random() < 0.08 else 1.0)
        col = pal[rs.integers(len(pal))]
        c.ellipse(x + r * 0.15, y + r * 0.25, r, r * 0.72, "#3b352d", alpha=0.45)          # тень снизу
        c.ellipse(x, y, r, r * 0.7, col, alpha=0.95)
        c.ellipse(x - r * 0.25, y - r * 0.25, r * 0.55, r * 0.35, "#b8a98c", alpha=0.5)    # тёплый блик сверху
    c.grain(0.035)
    h = _height_from(c, n, 0.75)
    _save(c, h, "ground_sand.png")


def main():
    print("текстуры земли…")
    grass()
    dry()
    earth()
    rock()
    sand()


if __name__ == "__main__":
    main()
