"""Палитра Ордо (ТЗ 2.1, 2.2, 11.1). Цвета в sRGB, строки #rrggbb.

Земля темнее и спокойнее, юниты светлее и насыщеннее (ТЗ 11.2).
"""

# Цвета сторон (ТЗ 2.1, 2.2)
KOKAND = {"main": "#2f8f74", "light": "#7fe8c8", "dark": "#17463a",
          "gold": "#c9a24a", "gold_dark": "#7d5a22", "tile": "#2aa39a", "tile_deep": "#145f63"}
KIPCHAK = {"main": "#b0392f", "light": "#ffa597", "dark": "#5a1712",
           "carmine": "#8e1f2f", "felt": "#e6dcc4", "felt_shadow": "#b9ab8e"}

# Земля: приглушённые охры, олива, серо-зелёный (ТЗ 11.1)
GROUND = {"ochre": "#8a7448", "ochre_light": "#a8915e", "olive": "#646238", "olive_dark": "#45462a",
          "greygreen": "#5d6a55", "greygreen_dark": "#3c463b", "dust": "#b39a6e",
          "earth": "#5e4a33", "rock": "#7a7466", "rock_dark": "#4b4a46", "snow": "#e8e6ea"}

# Материалы
MATERIAL = {"walnut": "#5a3b24", "walnut_dark": "#38231a", "wood_light": "#9a7a52",
            "brass": "#b58a3c", "copper": "#a3552c", "iron": "#5d6066", "steel": "#9aa1a8",
            "leather": "#6e4428", "leather_dark": "#45291a", "rope": "#a08a62",
            "felt_brown": "#5b3a22", "clay": "#a9805a", "brick": "#b0714a", "skin": "#b98466",
            "skin_dark": "#8a5a42", "horse_bay": "#6b3f26", "horse_chestnut": "#8a4a26",
            "horse_grey": "#a7a39a", "horse_black": "#2c2420", "wool": "#d8ccb0", "wool_dark": "#8d7f6a"}

# Свет заката и сумерек (ТЗ 11.1)
LIGHT = {"sun": "#ffb46e", "sun_hot": "#ffd9a0", "fill": "#4a7fa0", "shadow": "#2b3d5c",
         "rim": "#ffcf8a", "fire": "#ff8a3c", "sky_top": "#1f3554", "sky_mid": "#5e6f8a",
         "sky_horizon": "#f0a060", "haze": "#c99a78"}


def rgb(hex_color: str):
    """#rrggbb → (r, g, b) в 0..1."""
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb8(hex_color: str):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def godot_color(hex_color: str, a: float = 1.0) -> str:
    r, g, b = rgb(hex_color)
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, {a})"
