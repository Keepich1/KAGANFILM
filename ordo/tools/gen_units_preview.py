"""Быстрый предпросмотр юнитов без Godot: программная отрисовка позы покоя + доля цвета стороны.

    python3 tools/gen_units_preview.py kok_sarboz kip_jooker --out renders/units/preview.png
    python3 tools/gen_units_preview.py --all --out renders/units/sheet.png      # все юниты
    python3 tools/gen_units_preview.py kok_sarboz --variant=2 --views=front,q34,back,rts

Для каждого юнита — несколько видов (спереди, 3/4, сзади, сверху «как с камеры RTS») в позе покоя,
с атласом стороны, нарисованной тенью (COLOR.r) и простым тёплым/холодным светом заката.
Под кадрами — доля силуэта, занятая цветом стороны (COLOR.g, ТЗ 11.2: 20–30 %), и число
треугольников по частям. Это не замена кадрам Godot (tools/shot.sh), а быстрая проверка формы,
развёрток и разметки атласа между запусками генератора.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))

VIEWS = {
    # имя: (поворот камеры вокруг юнита, град; наклон вниз, град)
    "front": (0.0, 4.0),
    "q34": (38.0, 12.0),
    "side": (90.0, 4.0),
    "back": (180.0, 8.0),
    "rts": (25.0, 52.0),
    "top": (0.0, 80.0),
}

SUN = np.array([0.55, 0.45, 0.70])           # на солнце (в осях модели, юнит смотрит в +Z)
SUN = SUN / np.linalg.norm(SUN)
SUN_COL = np.array([1.0, 0.72, 0.5]) * 1.25
FILL_COL = np.array([0.26, 0.38, 0.52]) * 0.9


def _tex_sample(tex, uv):
    """Билинейная выборка (tex — float RGB, uv 0..1, v вниз как в glTF)."""
    h, w = tex.shape[:2]
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001)
    y = np.clip(uv[:, 1] * h - 0.5, 0, h - 1.001)
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    a = tex[y0, x0] * (1 - fx) + tex[y0, x0 + 1] * fx
    b = tex[y0 + 1, x0] * (1 - fx) + tex[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def render(m, tex, yaw_deg, pitch_deg, size=320, extent=None, variant=(0, 0), du=0.25, bg=(46, 44, 52), center=None):
    """Ортографический кадр меша в позе покоя. Возвращает (RGB uint8, маска силуэта, маска стороны)."""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    # направление от цели к камере
    to_cam = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)])
    right = np.cross([0.0, 1.0, 0.0], to_cam)
    right /= np.linalg.norm(right)
    up = np.cross(to_cam, right)
    P = m.P
    lo, hi = P.min(0), P.max(0)
    c = (lo + hi) / 2 if center is None else center
    ext = extent or float(np.max(hi - lo)) * 1.08
    sc = size / ext
    X = (P - c) @ right * sc + size / 2
    Y = -(P - c) @ up * sc + size / 2
    Z = (P - c) @ to_cam
    UV = m.UV.copy()
    hat = (m.C[:, 2] > 0.25) & (m.C[:, 2] < 0.75)
    coat = m.C[:, 2] >= 0.75
    UV[hat, 0] += variant[0] * du
    UV[coat, 0] += variant[1] * du
    img = np.zeros((size, size, 3))
    img[:] = np.array(bg) / 255.0
    zb = np.full((size, size), -1e9)
    sil = np.zeros((size, size), bool)
    side = np.zeros((size, size))
    N = m.N
    for f in m.F:
        a, b, cc = f
        # отсечение задних граней (как cull_back в шейдере толпы)
        fn = np.cross(P[b] - P[a], P[cc] - P[a])
        if np.dot(fn, to_cam) <= 0:
            continue
        xs, ys = np.array([X[a], X[b], X[cc]]), np.array([Y[a], Y[b], Y[cc]])
        x0, x1 = max(int(np.floor(xs.min())), 0), min(int(np.ceil(xs.max())), size - 1)
        y0, y1 = max(int(np.floor(ys.min())), 0), min(int(np.ceil(ys.max())), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-12:
            continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        w2 = 1 - w0 - w1
        ins = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not ins.any():
            continue
        z = w0 * Z[a] + w1 * Z[b] + w2 * Z[cc]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        ok = ins & (z > sub)
        if not ok.any():
            continue
        iy, ix = np.nonzero(ok)
        W = np.stack([w0[ok], w1[ok], w2[ok]], 1)
        uv = W @ np.stack([UV[a], UV[b], UV[cc]])
        nrm = W @ np.stack([N[a], N[b], N[cc]])
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        col = W @ np.stack([m.C[a], m.C[b], m.C[cc]])
        alb = _tex_sample(tex, uv) * col[:, :1]
        # как crowd.gdshader: насыщенность +22 %, подъём яркости +20 %
        l = alb @ np.array([0.299, 0.587, 0.114])
        alb = (l[:, None] + (alb - l[:, None]) * 1.22) * 1.2
        ndl = nrm @ SUN
        band = np.clip((ndl + 0.15) / 0.3, 0, 1)
        band = band * band * (3 - 2 * band)
        form = 0.62 + 0.38 * np.clip(ndl * 0.5 + 0.5, 0, 1)
        lit = SUN_COL * (band * form)[:, None] + FILL_COL * (0.75 + 0.25 * nrm[:, 1:2])
        lit += np.array([1.0, 0.55, 0.3]) * (band * (1 - band) * 0.9)[:, None]
        rim = np.clip(1 - np.abs(nrm @ to_cam), 0, 1) ** 3 * 0.5
        rgb = alb * lit + rim[:, None] * np.array([1.0, 0.8, 0.55]) * band[:, None]
        rgb = rgb / (1 + rgb * 0.35)  # мягкая тональная кривая
        img[y0 + iy, x0 + ix] = rgb
        sub[iy, ix] = z[ok]
        sil[y0 + iy, x0 + ix] = True
        side[y0 + iy, x0 + ix] = np.clip(col[:, 1], 0, 1)
    out = (np.clip(img, 0, 1) ** (1 / 1.25) * 255).astype(np.uint8)
    return out, sil, side


def coverage(sil, side):
    n = sil.sum()
    return float((side * sil).sum() / max(n, 1))


def part_counts(m, names):
    part = np.round(m.UV2[m.F[:, 0], 0]).astype(int)
    out = {}
    for p in np.unique(part):
        out[names[p] if p < len(names) else str(p)] = int((part == p).sum())
    return out


def build_unit(uid, d):
    import gen_units as U
    return U.build(uid, d)


def atlas_image(A, texdir=None):
    p = os.path.join(texdir or os.path.join(ROOT, "assets/textures/units"), A.name + ".png")
    im = Image.open(p).convert("RGB")
    im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255.0


def main(argv):
    import gen_units as U
    from gen_units_kit import HUMAN_PARTS, RIDER_PARTS, SHEEP_PARTS
    ap = argparse.ArgumentParser()
    ap.add_argument("units", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "renders/units/preview.png"))
    ap.add_argument("--views", default="front,q34,back,rts")
    ap.add_argument("--variant", default="0")
    ap.add_argument("--size", type=int, default=300)
    ap.add_argument("--lod", type=float, default=1.0)
    ap.add_argument("--tex-dir", default=None, help="папка с атласами (по умолчанию assets/textures/units)")
    ap.add_argument("--zoom", default=None, help="head — крупно голова и руки (верх фигуры)")
    a = ap.parse_args(argv)
    units = list(U.UNITS) if a.all or not a.units else a.units
    views = a.views.split(",")
    var = [int(v) for v in a.variant.split(",")]
    texcache = {}
    rows = []
    for uid in units:
        m, A = build_unit(uid, a.lod)
        if A.name not in texcache:
            texcache[A.name] = atlas_image(A, a.tex_dir)
        tex = texcache[A.name]
        kind = U.UNITS[uid][0]
        names = RIDER_PARTS if kind in ("rider", "horse") else (SHEEP_PARTS if kind == "sheep" else HUMAN_PARTS)
        lo, hi = m.P.min(0), m.P.max(0)
        ext = float(max(hi[1] - lo[1], hi[2] - lo[2], hi[0] - lo[0])) * 1.06
        center = None
        if a.zoom == "head":
            ext = 0.75
            hy = 2.25 if kind == "rider" else 1.62
            center = np.array([0.0, hy - 0.25, 0.0])
        for v in var:
            tiles, covs = [], []
            for vn in views:
                yaw, pitch = VIEWS[vn]
                im, sil, side = render(m, tex, yaw, pitch, a.size, ext, (v, v), center=center)
                tiles.append(im)
                covs.append(coverage(sil, side))
            row = np.concatenate(tiles, 1)
            label = f"{uid}  v{v}  {m.tris} tris  side: " + "  ".join(f"{vn} {c:.0%}" for vn, c in zip(views, covs))
            rows.append((row, label, part_counts(m, names)))
            print(label)
    W = max(r[0].shape[1] for r in rows)
    H = sum(r[0].shape[0] + 34 for r in rows)
    sheet = Image.new("RGB", (W, H), (30, 30, 34))
    dr = ImageDraw.Draw(sheet)
    y = 0
    for row, label, pc in rows:
        sheet.paste(Image.fromarray(row), (0, y))
        dr.text((6, y + row.shape[0] + 2), label, fill=(235, 225, 200))
        dr.text((6, y + row.shape[0] + 17), " ".join(f"{k}:{v}" for k, v in pc.items()), fill=(160, 160, 170))
        y += row.shape[0] + 34
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    sheet.save(a.out)
    print("кадр", a.out)


if __name__ == "__main__":
    main(sys.argv[1:])
