"""Costruisce icon_index.json: nome icona -> texture DDS + coordinate UV.

Gli atlas del gioco sono coppie di file con lo stesso nome base:
  Public/<mod>/GUI/<atlas>.lsx                  mappa: MapKey -> U1/V1/U2/V2
  Public/<mod>/Assets/Textures/Icons/<atlas>.dds  texture

I file vanno prima estratti dai .pak (divine.exe) dentro icon_assets/; questo
script scansiona quella cartella e scrive l'indice che app.py usa per
ritagliare i PNG a richiesta. Rilanciarlo dopo ogni nuova estrazione.
(In alternativa: trascina la cartella degli atlas sulla finestra dell'app
desktop, che fa la stessa cosa.)

Uso:
    python tools/build_icon_index.py [cartella_atlas]
"""

from __future__ import annotations

import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE))

from icon_indexer import build_index  # noqa: E402


def main() -> None:
    assets = Path(sys.argv[1]) if len(sys.argv) > 1 else BASE / "icon_assets"
    if not assets.is_dir():
        print(f"cartella non trovata: {assets}")
        raise SystemExit(1)
    out = BASE / "icon_index.json"
    n_icons, n_atlases = build_index(assets, out)
    print(f"\n{n_icons} icone da {n_atlases} atlas -> {out.name}")


if __name__ == "__main__":
    main()
