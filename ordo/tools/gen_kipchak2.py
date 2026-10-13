"""Лагерь кыпчаков, вторая очередь (экономика и укрепления): постройки, стройки, руины,
месторождения камня и золота, сцены-обёртки.

    python3 tools/gen_kipchak2.py                    # всё
    python3 tools/gen_kipchak2.py models             # постройки и укрепления (+ _lod1, _site, _ruin)
    python3 tools/gen_kipchak2.py models ken chep    # только эти (и их стройки/руины)
    python3 tools/gen_kipchak2.py deposits           # месторождения (текстура + модели)
    python3 tools/gen_kipchak2.py scenes             # сцены-обёртки scenes/kipchak2/*.tscn

Запуск из папки ordo/. Всё детерминировано (зёрна), результат коммитится.
Работников и инструменты делает tools/gen_units_work.py.
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MODELS = os.path.join(ROOT, "assets/models/kipchak")


def build_models(only=None):
    import gen_kipchak2_build as B
    import gen_kipchak2_fort as F
    from gen_kipchak2_kit import report, write_model
    jobs = dict(B.JOBS)
    jobs.update(F.JOBS)
    for name, fn in jobs.items():
        base = name.split("_")[0]
        if only and name not in only and base not in only:
            continue
        t0 = None
        for lod in (0, 1):
            out = fn(lod)
            nodes, groups = out if isinstance(out, tuple) else (out, None)
            path, t = write_model(MODELS, name if lod == 0 else name + "_lod1", nodes, groups)
            report(path, t, t0)
            if lod == 0:
                t0 = t


def main(argv):
    what = {a for a in argv if a in ("models", "deposits", "scenes")} or {"models", "deposits", "scenes"}
    only = [a for a in argv if a not in ("models", "deposits", "scenes")]
    t0 = time.time()
    if "models" in what:
        print("Постройки и укрепления…")
        build_models(only)
    if "deposits" in what:
        import gen_kipchak2_deposit as D
        print("Месторождения…")
        D.build_all()
    if "scenes" in what:
        import gen_kipchak2_scene as S
        print("Сцены-обёртки…")
        S.build_all()
    print(f"Готово за {time.time() - t0:.1f} с")


if __name__ == "__main__":
    main(sys.argv[1:])
