"""Проверка моделей по бюджетам ТЗ 11.5 и формату 11.6.

    python3 tools/check_budgets.py            # все assets/models/**/*.glb

Категория берётся из имени файла (см. CATEGORY). LOD1 должен иметь 40–55% треугольников LOD0.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from glb import read_glb_stats  # noqa: E402

# (телефон мин, телефон макс, ПК мин, ПК макс) — ТЗ 11.5
BUDGET = {
    "deposit": (400, 800, 600, 1500),
    "wall": (50, 150, 100, 300),
    "gate_tower": (800, 1500, 1500, 3000),
    "small": (800, 1500, 1500, 3000),
    "medium": (1500, 3000, 3000, 6000),
    "main": (3000, 5000, 6000, 10000),
    "infantry": (150, 300, 300, 600),
    "rider": (400, 600, 800, 1200),
    # не из таблицы ТЗ 11.5 — свои пределы среза для мелочей, животных и природы
    "prop": (0, 400, 0, 600),            # костёр, казан, поленница, кошмы, сено, сёдла
    "prop_large": (0, 800, 0, 1500),     # туг, арба
    "animal": (0, 300, 0, 600),          # овца, конь без всадника
    "tree": (0, 300, 0, 600),            # тополь, ива, арча, карагач
    "rock": (0, 150, 0, 300),
}
CATEGORY = {
    "devor": "wall", "tosh": "wall", "chep": "wall",
    "darvoza": "gate_tower", "darbaza": "gate_tower", "burj": "gate_tower", "munara": "gate_tower",
    "boz": "small", "uy": "small", "ken": "small", "ombor": "small", "tegirmon": "small",
    "kazarma": "medium", "otxona": "medium", "jooker": "medium", "jylky": "medium", "koroo": "medium",
    "topxona": "medium",
    "urda": "main", "ordo": "main", "kurultai": "main",
    "campfire": "prop", "kazan": "prop", "woodpile": "prop", "felt_rolls": "prop", "hay": "prop",
    "saddle_rack": "prop", "tug": "prop_large", "arba": "prop_large",
    "sheep": "animal", "horse": "animal",
    "poplar": "tree", "willow": "tree", "juniper": "tree", "elm": "tree",
    # экономика, Сб. 1 (ECONOMY.md §11)
    "tosh_end": "wall", "devor_end": "wall", "dala": "small", "xumdon": "small", "bozor": "medium",
    "aryk": "prop", "aryk_turn": "prop", "tugon": "prop", "munara_arba": "prop_large",
}
UNIT_RIDER = ("sayisker", "atchan", "chabuul", "jüz", "juz", "navkar", "yuzboshi", "kolbashchy", "rider")


def category(name):
    base = name.replace("_lod1", "")
    # стройка, руины, стадии поля и торцы стен считаются по своей постройке
    base = re.sub(r"_(site|ruin|s[0-9]|d[0-9])$", "", base)
    if base in CATEGORY:
        return CATEGORY[base]
    if base.startswith("deposit_"):
        return "deposit"
    if base.startswith("rock_"):
        return "rock"
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
                if ok and s["triangles"] < lo_p:
                    line += "  (меньше нижней границы — можно добавить деталей)"
                bad += not ok
        if s["min"][1] < -0.05:
            line += "  ниже земли!"
        print(line)
    print("Нарушений:", bad)
    return bad


if __name__ == "__main__":
    sys.exit(1 if main(os.path.join(os.path.dirname(__file__), "..")) else 0)
