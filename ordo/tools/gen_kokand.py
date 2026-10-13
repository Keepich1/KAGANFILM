"""Город Коканда (этап «экономика»): атлас, здания, укрепления, поля, сцены-обёртки.

    python3 tools/gen_kokand.py                  # всё
    python3 tools/gen_kokand.py atlas            # только атлас
    python3 tools/gen_kokand.py models           # все модели (атлас уже есть)
    python3 tools/gen_kokand.py models urda tosh # выбранные модели (с их _lod1, _site, _ruin)
    python3 tools/gen_kokand.py scenes           # обёртки scenes/kokand/*.tscn

Запуск из папки ordo/. Всё детерминировано (зёрна), результат коммитится.
Тестовую сцену scenes/test/kokand_look.tscn собирает её скрипт (раскладка города — в
scenes/test/kokand_look.gd), генерировать её не нужно.
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TEX = os.path.join(ROOT, "assets/textures/kokand")
MODELS = os.path.join(ROOT, "assets/models/kokand")
SCENES = os.path.join(ROOT, "scenes/kokand")


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
    what = [a for a in argv if a in ("atlas", "models", "scenes")] or ["atlas", "models", "scenes"]
    names = [a for a in argv if a not in ("atlas", "models", "scenes")]
    t0 = time.time()
    if "atlas" in what:
        import gen_kokand_atlas as A
        print("Атлас Коканда…")
        A.build(os.path.join(TEX, "atlas.png"), only=names or None)
        texture_import(os.path.join(TEX, "atlas.png"))
        if not names:
            for path in A.build_decals(TEX):
                texture_import(path)
    if "models" in what:
        import gen_kokand_models as M
        print("Модели…")
        M.build_all(MODELS, only=names or None)
    if "scenes" in what:
        import gen_kokand_scenes as S
        print("Сцены-обёртки…")
        S.build_all(SCENES)
    print(f"Готово за {time.time() - t0:.1f} с")


if __name__ == "__main__":
    main(sys.argv[1:])
