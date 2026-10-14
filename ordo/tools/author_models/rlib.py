"""Мини-рендер для проверки: ортографический, z-буфер, текстура + простой свет."""
import math, numpy as np
from PIL import Image

def tex_sample(tex, uv):
    h, w = tex.shape[:2]
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001); y = np.clip(uv[:, 1] * h - 0.5, 0, h - 1.001)
    x0, y0 = x.astype(int), y.astype(int); fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    t = lambda yy, xx: tex[yy, xx].astype(np.float32) / 255.0
    a = t(y0, x0) * (1 - fx) + t(y0, x0 + 1) * fx
    b = t(y0 + 1, x0) * (1 - fx) + t(y0 + 1, x0 + 1) * fx
    return a * (1 - fy) + b * fy

def vnormals(P, F):
    fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    N = np.zeros_like(P)
    for k in range(3): np.add.at(N, F[:, k], fn)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)

def render(P, F, UV, tex, yaw_deg, pitch_deg=5.0, size=384, center=None, ext=None, wire=False, FUV=None, N=None):
    """FUV: индексы UV по граням (если UV раздельные), иначе UV по вершинам F."""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    to_cam = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)])
    right = np.cross([0.0, 1.0, 0.0], to_cam); right /= np.linalg.norm(right)
    up = np.cross(to_cam, right)
    c = center if center is not None else (P.min(0) + P.max(0)) / 2
    ext = ext or float(np.max(P.max(0) - P.min(0))) * 1.08
    sc = size / ext
    X = (P - c) @ right * sc + size / 2; Y = -(P - c) @ up * sc + size / 2; Z = (P - c) @ to_cam
    if N is None: N = vnormals(P, F)
    FUV = F if FUV is None else FUV
    sun = np.array([0.5, 0.55, 0.67]); sun /= np.linalg.norm(sun)
    img = np.zeros((size, size, 3), np.float32); img[:] = np.array([0.80, 0.79, 0.76])
    zb = np.full((size, size), -1e9, np.float32)
    for fi in range(len(F)):
        a, b, cc = F[fi]; ua, ub, uc = FUV[fi]
        fn = np.cross(P[b] - P[a], P[cc] - P[a])
        if np.dot(fn, to_cam) <= 0: continue
        xs = np.array([X[a], X[b], X[cc]]); ys = np.array([Y[a], Y[b], Y[cc]])
        x0, x1 = max(int(np.floor(xs.min())), 0), min(int(np.ceil(xs.max())), size - 1)
        y0, y1 = max(int(np.floor(ys.min())), 0), min(int(np.ceil(ys.max())), size - 1)
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-12: continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        w2 = 1 - w0 - w1
        ins = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not ins.any(): continue
        z = w0 * Z[a] + w1 * Z[b] + w2 * Z[cc]
        sub = zb[y0:y1 + 1, x0:x1 + 1]; ok = ins & (z > sub)
        if not ok.any(): continue
        iy, ix = np.nonzero(ok)
        W = np.stack([w0[ok], w1[ok], w2[ok]], 1)
        uv = W @ np.stack([UV[ua], UV[ub], UV[uc]])
        nrm = W @ np.stack([N[a], N[b], N[cc]]); nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        alb = tex_sample(tex, uv)
        ndl = nrm @ sun
        lit = 0.55 + 0.55 * np.clip(ndl, 0, 1)
        rgb = alb * lit[:, None]
        if wire:
            e = np.minimum(np.minimum(w0[ok], w1[ok]), w2[ok]) * abs(d) / max(np.ptp(xs), np.ptp(ys), 1e-6)
            rgb = np.where((e < 0.9)[:, None], rgb * 0.35, rgb)
        img[y0 + iy, x0 + ix] = rgb; sub[iy, ix] = z[ok]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))

def row(imgs, gap=6, bg=(205, 202, 194)):
    w = sum(i.width for i in imgs) + gap * (len(imgs) - 1); h = max(i.height for i in imgs)
    out = Image.new('RGB', (w, h), bg); x = 0
    for i in imgs: out.paste(i, (x, 0)); x += i.width + gap
    return out
