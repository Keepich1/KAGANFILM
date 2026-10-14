"""Сарбоз из модели автора (src/kok_sarboz_src.glb, Seedream → 3D) → assets/models/units/kok_sarboz(_lod1).glb.

    pip install trimesh fast-simplification xatlas scipy embreex rtree
    python3 tools/author_models/build_sarboz.py

Шаги: масштаб и центр → руки в позу покоя скелета толпы (плечо–кисть, длина руки) → упрощение сетки
(520 / 260 треуг.) → новая развёртка → перенос рисунка лучом снаружи (запекание) → сглаженные нормали
с высокой модели → части тела (UV2.x) и веса сгиба (UV2.y) → ружьё и шомпол из gen_units → glb.
"""
import os, sys, numpy as np, trimesh, fast_simplification, xatlas
from scipy.spatial import cKDTree
from PIL import Image
ORDO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../..'))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ORDO + '/tools'); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rlib
from meshkit import Mesh
from glb import write_glb, Material
import gen_units as GU
from gen_units_kit import HP, HUMAN_PIV, ensure_import, GLB_IMPORT, PNG_IMPORT

H_TOTAL = 1.86
_src = trimesh.load(os.path.join(HERE, 'src/kok_sarboz_src.glb'), force='scene').to_geometry()
P0 = np.asarray(_src.vertices, float).copy(); F0 = np.asarray(_src.faces)
UV0 = np.asarray(_src.visual.uv, float).copy(); UV0[:, 1] = 1 - UV0[:, 1]
tex_hi = np.asarray(_src.visual.material.baseColorTexture.convert('RGB').resize((2048, 2048), Image.LANCZOS))

# 1) масштаб и центр
s = H_TOTAL / P0[:, 1].max(); P0 *= s
P0[:, 0] -= (P0[:, 0].min() + P0[:, 0].max()) / 2
chest = P0[np.abs(P0[:, 1] - 1.25) < 0.05]
P0[:, 2] -= (chest[:, 2].min() + chest[:, 2].max()) / 2

# 2) руки → поза покоя скелета (плечо–кисть)
def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(np.dot(a, b)); k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)

P = P0.copy(); arm_w = np.zeros(len(P))   # +1 левая рука, −1 правая, 0 — не рука
for sx, sh, hd in ((1, 'SHOULDER_L', 'HAND_L'), (-1, 'SHOULDER_R', 'HAND_R')):
    hand = P0[(P0[:, 1] > 0.70) & (P0[:, 1] < 0.82) & (P0[:, 0] * sx > 0.30)]
    Hm = hand.mean(0)
    Sm = np.array([0.20 * sx, 1.42, 0.0])
    Sr, Hr = np.array(HUMAN_PIV[sh]), np.array(HUMAN_PIV[hd])
    am = (Hm - Sm); Lm = np.linalg.norm(am); am /= Lm
    ar = (Hr - Sr); Lr = np.linalg.norm(ar); ar /= Lr
    k = Lr / Lm; R = rot_between(am, ar)
    rel = P0 - Sm; t = rel @ am
    radial = rel - t[:, None] * am
    dist = np.linalg.norm(radial, axis=1)
    w = np.clip((0.13 - dist) / 0.04, 0, 1) * np.clip((t - 0.03) / 0.15, 0, 1) * (P0[:, 0] * sx > 0.12)
    w = w * w * (3 - 2 * w)
    newp = Sr + (t * k)[:, None] * ar + radial @ R.T
    P += w[:, None] * (newp - P0)
    # принадлежность к руке (по исходной позе): у плеча рука прижата к телу — граница по ширине торса
    member = (dist < 0.13) & (t > 0.04) & (P0[:, 0] * sx > np.where(P0[:, 1] > 1.08, 0.205, 0.12))
    arm_w[member] = sx
    print(sh, 'длина руки модели', round(Lm, 3), '→', round(Lr, 3), 'кисть модели', Hm.round(3))

_hm = trimesh.Trimesh(P, F0, process=True); _hm.merge_vertices(merge_tex=True, merge_norm=True)
hi_n = rlib.vnormals(np.asarray(_hm.vertices), np.asarray(_hm.faces)) * 1.0
hi_ptree = cKDTree(np.asarray(_hm.vertices))

def lowpoly(target, texsize):
    hm = trimesh.Trimesh(P, F0, process=True); hm.merge_vertices(merge_tex=True, merge_norm=True)
    Pm, Fm = np.asarray(hm.vertices), np.asarray(hm.faces)
    Pl, Fl = fast_simplification.simplify(Pm.astype(np.float32), Fm.astype(np.int64), target_reduction=1 - target / len(Fm), agg=7)
    lm = trimesh.Trimesh(Pl, Fl, process=True); lm.remove_unreferenced_vertices()
    Pl, Fl = np.asarray(lm.vertices, float), np.asarray(lm.faces)
    vmap, Fi, UVl = xatlas.parametrize(Pl.astype(np.float32), Fl.astype(np.uint32))
    # нормали — с высокой модели, сглаженные в радиусе ~6 см: без граней на контровом свете
    Nm = np.zeros_like(Pl)
    for i, nb in enumerate(hi_ptree.query_ball_point(Pl, r=0.035)):
        Nm[i] = hi_n[nb].sum(0) if len(nb) else 0
    own = rlib.vnormals(Pl, Fl)
    Nm = Nm / np.maximum(np.linalg.norm(Nm, axis=1, keepdims=True), 1e-9)
    Nm = Nm + own; Nm /= np.maximum(np.linalg.norm(Nm, axis=1, keepdims=True), 1e-9)
    bad = (Nm * own).sum(1) < 0.2
    Nm[bad] = own[bad]
    Pv, Nv = Pl[vmap], Nm[vmap]
    # запекание лучом снаружи
    from trimesh.ray.ray_pyembree import RayMeshIntersector
    hmesh = trimesh.Trimesh(P, F0, process=False); rmi = RayMeshIntersector(hmesh)
    pts, fid = trimesh.sample.sample_surface(hmesh, 1_500_000, seed=3)
    bary = trimesh.triangles.points_to_barycentric(P[F0[fid]], pts)
    cols = rlib.tex_sample(tex_hi, np.einsum('ij,ijk->ik', bary, UV0[F0[fid]])); tree = cKDTree(pts)
    S = texsize; img = np.zeros((S, S, 3), np.float32); filled = np.zeros((S, S), bool); U = UVl * S
    for f in Fi:
        xs, ys = U[f, 0], U[f, 1]
        x0, x1 = max(int(np.floor(xs.min())) - 1, 0), min(int(np.ceil(xs.max())) + 1, S - 1)
        y0, y1 = max(int(np.floor(ys.min())) - 1, 0), min(int(np.ceil(ys.max())) + 1, S - 1)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        dd = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(dd) < 1e-12: continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / dd
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / dd
        w2 = 1 - w0 - w1; e = -0.6 / max(np.ptp(xs), np.ptp(ys), 1.0)
        ins = (w0 >= e) & (w1 >= e) & (w2 >= e)
        if not ins.any(): continue
        iy, ix = np.nonzero(ins)
        W = np.clip(np.stack([w0[ins], w1[ins], w2[ins]], 1), 0, 1); W /= W.sum(1, keepdims=True)
        p = W @ Pv[f]; n = W @ Nv[f]; n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        org = p + n * 0.06
        locs, ri, ti = rmi.intersects_location(org, -n, multiple_hits=False)
        col = np.zeros((len(p), 3), np.float32); hit = np.zeros(len(p), bool)
        if len(ri):
            ok = np.linalg.norm(locs - org[ri], axis=1) < 0.13
            ri, ti, lc = ri[ok], ti[ok], locs[ok]
            b2 = trimesh.triangles.points_to_barycentric(P[F0[ti]], lc)
            col[ri] = rlib.tex_sample(tex_hi, np.einsum('ij,ijk->ik', b2, UV0[F0[ti]])); hit[ri] = True
        if (~hit).any():
            _, idx = tree.query(p[~hit]); col[~hit] = cols[idx]
        img[y0 + iy, x0 + ix] = col; filled[y0 + iy, x0 + ix] = True
    for _ in range(10):
        m = ~filled
        if not m.any(): break
        acc = np.zeros_like(img); cnt = np.zeros((S, S), np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * np.roll(np.roll(filled, dy, 0), dx, 1)[..., None]
            cnt += np.roll(np.roll(filled, dy, 0), dx, 1)
        new = m & (cnt > 0); img[new] = acc[new] / cnt[new][:, None]; filled |= new
    img = np.clip(img, 0, 1); img = (img + 0.06 * (1 - img)) * 1.08
    return Pv, Fi.astype(np.int64), UVl, Nv, (np.clip(img, 0, 1) * 255).astype(np.uint8)

# соседи по высокой модели — вес руки для частей
hi_tree = cKDTree(P)

def parts_and_weights(Pv):
    _, idx = hi_tree.query(Pv); aw = arm_w[idx]
    part = np.zeros(len(Pv)); wgt = np.zeros(len(Pv))
    y, x = Pv[:, 1], Pv[:, 0]
    for i in range(len(Pv)):
        if aw[i] != 0:
            L = aw[i] > 0
            Sr = np.array(HUMAN_PIV['SHOULDER_L' if L else 'SHOULDER_R']); Er = np.array(HUMAN_PIV['ELBOW_L' if L else 'ELBOW_R'])
            Hr = np.array(HUMAN_PIV['HAND_L' if L else 'HAND_R'])
            a = (Hr - Sr) / np.linalg.norm(Hr - Sr); t = (Pv[i] - Sr) @ a; te = (Er - Sr) @ a
            if t < te:
                part[i] = HP['UARM_L' if L else 'UARM_R']
                ws = 0.42 * np.clip(1 - max(t, 0) / 0.13, 0, 1); we = 0.5 * np.clip(1 - max(te - t, 0) / 0.1, 0, 1)
                wgt[i] = max(ws, we)
            else:
                part[i] = HP['FARM_L' if L else 'FARM_R']; wgt[i] = 0.5 * np.clip(1 - max(t - te, 0) / 0.1, 0, 1)
        elif y[i] > 1.53: part[i] = HP['HEAD']
        elif y[i] > 1.06: part[i] = HP['CHEST']
        elif y[i] > 0.93: part[i] = HP['PELVIS']
        elif y[i] > 0.29:
            part[i] = HP['SKIRT_L' if x[i] >= 0 else 'SKIRT_R']; wgt[i] = np.clip((1.03 - y[i]) / (1.03 - 0.30), 0, 1)
        else:
            part[i] = HP['SHIN_L' if x[i] >= 0 else 'SHIN_R']
    wgt = wgt * wgt * (3 - 2 * wgt) if False else wgt
    return part, np.clip(wgt, 0, 1)

def side_mask(tex, uv):
    c = rlib.tex_sample(tex, uv); mx, mn = c.max(1), c.min(1); sat = (mx - mn) / np.maximum(mx, 1e-6)
    return ((c[:, 1] > c[:, 0] * 1.2) & (c[:, 1] > c[:, 2] * 1.05) & (sat > 0.3)).astype(float)

atlas = Image.open(ORDO + '/assets/textures/units/kokand_units.png').convert('RGB')
out_tex = 'kok_sarboz_v2'
for lod, target, texsize, dd in ((0, 520, 1024, 1.0), (1, 260, 1024, 0.5)):
    Pv, Fi, UVl, Nv, body = lowpoly(target, texsize)
    part, wgt = parts_and_weights(Pv)
    body_m = Mesh(Pv, Fi, Nv, UVl.astype(float).copy(), np.stack([part, wgt], 1), np.ones((len(Pv), 4)))
    body_m.C[:, 1] = side_mask(body, UVl); body_m.C[:, 2] = 0.0; body_m.C[:, 3] = 0.0
    body_m.UV[:, 0] *= 0.5                                        # левая половина — тело
    W = HUMAN_PIV['HAND_R']
    wp = GU.musket(GU.KOK, HP['WEAPON'], W, dd) + GU.ramrod(GU.KOK, HP['ITEM'], W)
    wm = Mesh.merge(wp); wm.UV[:, 0] = 0.5 + wm.UV[:, 0] * 0.5     # правая — старый атлас (ружьё)
    m = Mesh.merge([body_m, wm])
    if lod == 0:
        teximg = Image.new('RGB', (2048, 1024)); teximg.paste(Image.fromarray(body).resize((1024, 1024), Image.LANCZOS), (0, 0))
        teximg.paste(atlas.resize((1024, 1024), Image.LANCZOS), (1024, 0))
        tp = ORDO + f'/assets/textures/units/{out_tex}.png'; teximg.save(tp); ensure_import(tp, PNG_IMPORT)
    name = 'kok_sarboz' + ('_lod1' if lod else '')
    p = ORDO + f'/assets/models/units/{name}.glb'
    write_glb(p, [(name, m, Material(out_tex, texture_uri=f'../../textures/units/{out_tex}.png', roughness=0.85))])
    ensure_import(p, GLB_IMPORT)
    cnt = {k: int((np.round(m.UV2[:, 0]) == v).sum()) for k, v in HP.items() if (np.round(m.UV2[:, 0]) == v).any()}
    print(name, 'треугольников', len(m.F), 'части', cnt)
