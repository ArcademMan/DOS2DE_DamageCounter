"""Scansione degli atlas estratti -> icon_index.json.

Gli atlas del gioco sono coppie di file con lo stesso nome base:
  .../GUI/<atlas>.lsx                       mappa: MapKey -> U1/V1/U2/V2
  .../Assets/Textures/Icons/<atlas>.dds     texture

Questo modulo e' condiviso tra tools/build_icon_index.py (riga di comando)
e desktop.py (drag-and-drop della cartella sull'app). L'indice scrive i
percorsi DDS assoluti, cosi' la cartella degli atlas puo' stare ovunque.
"""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def data_dir() -> Path:
    """Dove vivono icon_index.json e la cache dei PNG.

    Nell'exe PyInstaller i moduli stanno in _internal (sola lettura per
    convenzione): i dati dell'utente vanno accanto all'eseguibile. In
    sviluppo e' semplicemente la cartella del progetto.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    return Path(__file__).resolve().parent


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


def build_index(assets_root: Path, out_path: Path,
                log=print) -> tuple[int, int]:
    """Scansiona assets_root e scrive l'indice. Ritorna (icone, atlas)."""
    index: dict[str, dict] = {}
    n_atlases = 0
    dds_by_stem = {p.stem.lower(): p for p in assets_root.rglob("*.dds")}
    for lsx in sorted(assets_root.rglob("*.lsx")):
        dds = dds_by_stem.get(lsx.stem.lower())
        if dds is None:
            log(f"salto {lsx.name}: nessuna texture {lsx.stem}.dds")
            continue
        try:
            icons = parse_atlas(lsx)
        except ET.ParseError as exc:
            log(f"salto {lsx.name}: XML non valido ({exc})")
            continue
        if not icons:
            continue
        n_atlases += 1
        for key, uv in icons.items():
            uv["dds"] = str(dds.resolve())
            index[key] = uv  # in caso di doppioni vince l'ultimo atlas
        log(f"{lsx.name}: {len(icons)} icone -> {dds.name}")
    if index:
        out_path.write_text(json.dumps(index), encoding="utf-8")
    return len(index), n_atlases
