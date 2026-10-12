"""Проверка моделей по бюджетам ТЗ 11.5 и формату 11.6.

    python3 tools/check_budgets.py            # все assets/models/**/*.glb

Категория берётся из имени файла (см. CATEGORY). LOD1 должен иметь 40–55% треугольников LOD0.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from glb import read_glb_stats  # noqa: E402

# (телефон мин, телефон макс, ПК мин, ПК макс) — ТЗ 11.5
BUDGET = {
    "wall": (50, 150, 100, 300),
    "gate_tower": (800, 1500, 1500, 3000),
    "small": (800, 1500, 1500, 3000),
    "medium": (1500, 3000, 3000, 6000),
    "main": (3000, 5000, 6000, 10000),
    "infantry": (150, 300, 300, 600),
    "rider": (400, 600, 800, 1200),
}
CATEGORY = {
    "devor": "wall", "tosh": "wall", "chep": "wall",
    "darvoza": "gate_tower", "darbaza": "gate_tower", "burj": "gate_tower", "munara": "gate_tower",
    "boz": "small", "uy": "small", "ken": "small", "ombor": "small", "tegirmon": "small",
    "kazarma": "medium", "otxona": "medium", "jooker": "medium", "jylky": "medium", "koroo": "medium",
    "topxona": "medium",
    "urda": "main", "ordo": "main", "kurultai": "main",
}
UNIT_RIDER = ("sayisker", "atchan", "chabuul", "jüz", "juz", "navkar", "yuzboshi", "kolbashchy", "rider")


def category(name):
    base = name.replace("_lod1", "")
    if base in CATEGORY:
        return CATEGORY[base]
    if base.startswith(("kip_", "kok_")):
        return "rider" if any(k in base for k in UNIT_RIDER) else "infantry"
    return None


def main(root):
    files = sorted(glob.glob(os.path.join(root, "assets/models/**/*.glb"), recursive=True))
    stats = {os.path.splitext(os.path.basename(f))[0]: (f, read_glb_stats(f)) for f in files}
    bad = 0
    for name, (f, s) in stats.items():
        cat = category(name)
        line = f"{os.path.relpath(f, root):48s} {s['triangles']:6d} треуг. {s['materials']} мат. размер {s['size']}"
        if cat:
            lo_m, hi_m, lo_p, hi_p = BUDGET[cat]
            if name.endswith("_lod1"):
                base = stats.get(name[:-5])
                if base:
                    r = s["triangles"] / max(base[1]["triangles"], 1)
                    ok = 0.40 <= r <= 0.55 or s["triangles"] <= hi_m
                    line += f"  LOD1 {r:.0%} от LOD0 {'ok' if ok else '!!'}"
                    bad += not ok
            else:
                ok = s["triangles"] <= hi_p
                line += f"  [{cat}: ПК {lo_p}–{hi_p}] {'ok' if ok else 'ПРЕВЫШЕН'}"
                bad += not ok
        if s["min"][1] < -0.05:
            line += "  ниже земли!"
        print(line)
    print("Нарушений:", bad)
    return bad


if __name__ == "__main__":
    sys.exit(1 if main(os.path.join(os.path.dirname(__file__), "..")) else 0)
