"""Лагерь кыпчаков (срез стиля, ТЗ этап 0): атлас, модели, дым и огонь.

    python3 tools/gen_camp.py                 # всё
    python3 tools/gen_camp.py atlas           # только атлас
    python3 tools/gen_camp.py models          # только модели (атлас уже есть)
    python3 tools/gen_camp.py fx              # дым, пламя, следы на земле
    python3 tools/gen_camp.py scene           # сцена лагеря scenes/camp/camp.tscn

Запуск из папки ordo/. Всё детерминировано (зёрна), результат коммитится.
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TEX = os.path.join(ROOT, "assets/textures/kipchak")
MODELS = os.path.join(ROOT, "assets/models/kipchak")


def texture_import(png_path, mipmaps=True, vram=True):
    """Настройки импорта текстуры для Godot: мип-карты и сжатие (BPTC/ASTC).
    Если .import уже есть — правим только эти параметры (uid и пути сохраняются)."""
    imp = png_path + ".import"
    want = {"compress/mode": "2" if vram else "0", "compress/high_quality": "true" if vram else "false",
            "mipmaps/generate": "true" if mipmaps else "false", "detect_3d/compress_to": "0"}
    if os.path.exists(imp):
        lines = open(imp, encoding="utf-8").read().splitlines()
        seen = set()
        for i, ln in enumerate(lines):
            k = ln.split("=", 1)[0]
            if k in want:
                lines[i] = f"{k}={want[k]}"
                seen.add(k)
        lines += [f"{k}={v}" for k, v in want.items() if k not in seen]
        text = "\n".join(lines) + "\n"
    else:
        text = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n' + \
               "".join(f"{k}={v}\n" for k, v in want.items())
    with open(imp, "w", encoding="utf-8") as f:
        f.write(text)


def main(argv):
    what = set(argv) or {"atlas", "models", "fx", "scene"}
    t0 = time.time()
    if "atlas" in what:
        import gen_camp_atlas as A
        print("Атлас кыпчаков…")
        A.build(os.path.join(TEX, "atlas.png"))
        texture_import(os.path.join(TEX, "atlas.png"))
    if "models" in what:
        import gen_camp_models as M
        print("Модели…")
        M.build_all(MODELS)
    if "fx" in what:
        import gen_camp_fx as F
        print("Дым, пламя, следы…")
        F.build_all(TEX)
    if "scene" in what:
        import gen_camp_scene as S
        print("Сцена лагеря…")
        S.build(os.path.join(ROOT, "scenes/camp/camp.tscn"))
    print(f"Готово за {time.time() - t0:.1f} с")


if __name__ == "__main__":
    main(sys.argv[1:])
