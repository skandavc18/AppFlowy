#!/usr/bin/env python3
"""Cuts the bundled variable Inter into the static faces AppFlowy registers.

Flutter keeps a variable face at its default instance whatever FontWeight a
style asks for, and fakes bold from w600 up, so Inter is registered as one
static face per FontWeight, each cut where AppFlowy's weight ladder puts it.
Text then renders at the same weight whether or not a style also sets the
`wght` axis.

Keep WEIGHT_AXIS in step with flowyFontWeightAxisValues in
packages/flowy_infra_ui/lib/style_widget/font_weight.dart and the font list in
pubspec.yaml, then run from frontend/appflowy_flutter (needs fontTools):

    python3 tool/fonts/build_inter_static.py
"""

import pathlib

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTER = ROOT / "assets" / "google_fonts" / "Inter"
OUT = INTER / "static"

# FontWeight -> wght. Nothing sets w100 or w200, and Flutter answers them
# with the w300 face rather than synthesizing a lighter one.
WEIGHT_AXIS = {300: 350, 400: 440, 500: 480, 600: 560, 700: 640, 800: 720, 900: 800}
# Inter's text optical size, which interface and body copy use.
TEXT_OPTICAL_SIZE = 14

SOURCES = (
    ("Inter-Variable.ttf", ""),
    ("Inter-VariableItalic.ttf", "-Italic"),
)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for stale in OUT.glob("Inter-*.ttf"):
        stale.unlink()
    for source, suffix in SOURCES:
        for weight, wght in WEIGHT_AXIS.items():
            font = TTFont(INTER / source)
            static = instancer.instantiateVariableFont(
                font,
                {"wght": wght, "opsz": TEXT_OPTICAL_SIZE},
            )
            # Flutter matches a face by the weight it declares and ignores
            # pubspec's `weight:`, so each cut declares the FontWeight it
            # stands in for. Left at its wght, w600 would land on the 640 cut.
            static["OS/2"].usWeightClass = weight
            target = OUT / f"Inter-{wght}{suffix}.ttf"
            static.save(target)
            print(f"{target.relative_to(ROOT)}  {target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
