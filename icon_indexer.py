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


def parse_atlas(lsx: Path) -> tuple[dict[str, dict], str | None]:
    """Ritorna (icone, percorso texture dichiarato nel TextureAtlasInfo)."""
    root = ET.parse(lsx).getroot()
    icons: dict[str, dict] = {}
    texture: str | None = None
    for node in root.iter("node"):
        node_id = node.get("id")
        if node_id == "TextureAtlasPath":
            for a in node.iter("attribute"):
                if a.get("id") == "Path" and a.get("value"):
                    texture = a.get("value")
            continue
        if node_id != "IconUV":
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
    return icons, texture


def build_index(assets_root: Path, out_path: Path,
                log=print) -> tuple[int, int]:
    """Scansiona assets_root e scrive l'indice. Ritorna (icone, atlas)."""
    index: dict[str, dict] = {}
    n_atlases = 0
    dds_by_stem: dict[str, list[Path]] = {}
    for p in assets_root.rglob("*.dds"):
        dds_by_stem.setdefault(p.stem.lower(), []).append(p)

    def nearest(lsx: Path, candidates: list[Path]) -> Path:
        # mod diverse riusano lo stesso nome atlas (es. newAtlas.dds):
        # scegli il dds che condivide piu' cartelle iniziali con l'lsx
        def shared(dds: Path) -> int:
            a, b = lsx.parent.parts, dds.parent.parts
            n = 0
            while n < min(len(a), len(b)) and a[n] == b[n]:
                n += 1
            return n
        return max(candidates, key=shared)

    def find_dds(lsx: Path, texture: str | None) -> Path | None:
        # il percorso dichiarato nell'lsx e' relativo alla radice della mod
        # (Public/<Mod>/): risali gli antenati finche' non combacia
        if texture:
            rel = texture.replace("\\", "/").lstrip("/")
            for anc in lsx.parents:
                cand = anc / rel
                if cand.is_file():
                    return cand
            stem = Path(rel).stem.lower()
        else:
            stem = lsx.stem.lower()
        candidates = dds_by_stem.get(stem)
        return nearest(lsx, candidates) if candidates else None

    for lsx in sorted(assets_root.rglob("*.lsx")):
        try:
            icons, texture = parse_atlas(lsx)
        except ET.ParseError as exc:
            log(f"salto {lsx.name}: XML non valido ({exc})")
            continue
        dds = find_dds(lsx, texture)
        if dds is None:
            log(f"salto {lsx.name}: nessuna texture "
                f"{texture or lsx.stem + '.dds'}")
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
