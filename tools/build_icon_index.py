"""Costruisce icon_index.json: nome icona -> texture DDS + coordinate UV.

Gli atlas del gioco sono coppie di file con lo stesso nome base:
  Public/<mod>/GUI/<atlas>.lsx                  mappa: MapKey -> U1/V1/U2/V2
  Public/<mod>/Assets/Textures/Icons/<atlas>.dds  texture

I file vanno prima estratti dai .pak (divine.exe) dentro icon_assets/; questo
script scansiona quella cartella e scrive l'indice che app.py usa per
ritagliare i PNG a richiesta. Rilanciarlo dopo ogni nuova estrazione.

Uso:
    python tools/build_icon_index.py
"""

from __future__ import annotations

import json
import xml.etree.ElementTree as ET
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
ASSETS = BASE / "icon_assets"
OUT = BASE / "icon_index.json"


def find_dds(name: str) -> Path | None:
    """Texture con lo stesso nome base dell'atlas, ovunque sia nell'albero."""
    for p in ASSETS.rglob(name + ".dds"):
        return p
    return None


def parse_atlas(lsx: Path) -> dict[str, dict]:
    root = ET.parse(lsx).getroot()
    icons: dict[str, dict] = {}
    for node in root.iter("node"):
        if node.get("id") != "IconUV":
            continue
        attrs = {a.get("id"): a.get("value") for a in node.iter("attribute")}
        key = attrs.get("MapKey")
        if not key:
            continue
        try:
            icons[key] = {
                "u1": float(attrs["U1"]),
                "v1": float(attrs["V1"]),
                "u2": float(attrs["U2"]),
                "v2": float(attrs["V2"]),
            }
        except (KeyError, ValueError):
            continue
    return icons


def main() -> None:
    index: dict[str, dict] = {}
    n_atlases = 0
    for lsx in sorted(ASSETS.rglob("*.lsx")):
        dds = find_dds(lsx.stem)
        if dds is None:
            print(f"salto {lsx.name}: nessuna texture {lsx.stem}.dds")
            continue
        icons = parse_atlas(lsx)
        if not icons:
            continue
        n_atlases += 1
        rel = str(dds.relative_to(BASE)).replace("\\", "/")
        for key, uv in icons.items():
            uv["dds"] = rel
            index[key] = uv  # in caso di doppioni vince l'ultimo atlas
        print(f"{lsx.name}: {len(icons)} icone -> {dds.name}")
    OUT.write_text(json.dumps(index), encoding="utf-8")
    print(f"\n{len(index)} icone da {n_atlases} atlas -> {OUT.name}")


if __name__ == "__main__":
    main()
