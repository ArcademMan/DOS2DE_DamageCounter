"""DamageCounter - desktop app.

Native window (Qt / PySide6) that runs the FastAPI server on an internal
thread and shows the dashboard inside the window itself: no terminal, no
browser. Settings (stats file, port) live in config.json next to this file.

Run:
    python desktop.py

Dependencies:
    pip install PySide6
"""

from __future__ import annotations

import json
import os
import socket
import sys
import threading
import time
from pathlib import Path

BASE_DIR = Path(__file__).parent
CONFIG_PATH = BASE_DIR / "config.json"

# Nelle build PyInstaller senza console sys.stdout/stderr sono None, e il
# formatter di uvicorn chiama sys.stdout.isatty() al primo log: crash
# all'avvio del server. Un devnull al posto di None accontenta chiunque
# provi a scrivere o interrogare i flussi standard.
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")  # noqa: SIM115
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")  # noqa: SIM115

DEFAULTS = {
    "port": 48124,
    # Empty = auto-detect from the Windows registry (see app.py).
    "stats_path": "",
}

# Stessa palette di static/style.css: la finestra deve sembrare parte
# della pagina, non una cornice estranea.
COLORS = {
    "bg": "#12131a",
    "panel": "#1a1c26",
    "panel2": "#212431",
    "line": "#2c3040",
    "text": "#e8eaf2",
    "muted": "#8b90a6",
    "accent": "#d4a04a",
}

QSS = f"""
QMainWindow, QDialog {{
    background: {COLORS["bg"]};
}}
QToolBar {{
    background: {COLORS["bg"]};
    border: none;
    border-bottom: 1px solid {COLORS["line"]};
    padding: 6px 10px;
    spacing: 6px;
}}
QToolBar QToolButton {{
    color: {COLORS["text"]};
    background: transparent;
    border: 1px solid transparent;
    border-radius: 7px;
    padding: 6px 14px;
    font-size: 13px;
}}
QToolBar QToolButton:hover {{
    background: {COLORS["panel2"]};
    border-color: {COLORS["line"]};
}}
QToolBar QToolButton:pressed {{
    color: {COLORS["accent"]};
}}
QStatusBar {{
    background: {COLORS["bg"]};
    color: {COLORS["muted"]};
    border-top: 1px solid {COLORS["line"]};
    font-size: 12px;
}}
QLabel {{
    color: {COLORS["text"]};
    font-size: 13px;
}}
QLineEdit, QSpinBox {{
    color: {COLORS["text"]};
    background: {COLORS["panel"]};
    border: 1px solid {COLORS["line"]};
    border-radius: 7px;
    padding: 7px 10px;
    selection-background-color: {COLORS["accent"]};
    selection-color: {COLORS["bg"]};
}}
QLineEdit:focus, QSpinBox:focus {{
    border-color: {COLORS["accent"]};
}}
QSpinBox::up-button, QSpinBox::down-button {{
    width: 0;
}}
QPushButton {{
    color: {COLORS["text"]};
    background: {COLORS["panel2"]};
    border: 1px solid {COLORS["line"]};
    border-radius: 7px;
    padding: 7px 18px;
    font-size: 13px;
}}
QPushButton:hover {{
    border-color: {COLORS["accent"]};
    color: {COLORS["accent"]};
}}
QPushButton:default {{
    background: {COLORS["accent"]};
    color: {COLORS["bg"]};
    border-color: {COLORS["accent"]};
    font-weight: 600;
}}
QMessageBox {{
    background: {COLORS["panel"]};
}}
"""


def load_config() -> dict:
    try:
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        cfg = {}
    return {**DEFAULTS, **cfg}


def save_config(cfg: dict) -> None:
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2), encoding="utf-8")


def port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(("127.0.0.1", port)) == 0


SERVER_LOG = BASE_DIR / "server_error.log"


def start_server(cfg: dict) -> str:
    """Start the backend in-process. Returns a status note.

    If the port already answers (server started by hand, or a second app
    instance) nothing is started: the window attaches to the existing one.

    Any failure ends up BOTH in the returned note and in server_error.log:
    the app has no console, so an unlogged exception would vanish.
    """
    if port_in_use(cfg["port"]):
        return "attached to already-running server"

    # DC_STATS_PATH must be set BEFORE importing app.py: the path is
    # resolved at import time.
    if cfg["stats_path"]:
        os.environ["DC_STATS_PATH"] = cfg["stats_path"]

    import traceback

    def log_failure(stage: str) -> str:
        detail = traceback.format_exc()
        try:
            SERVER_LOG.write_text(
                f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {stage}\n{detail}",
                encoding="utf-8")
        except OSError:
            pass
        last = detail.strip().splitlines()[-1] if detail.strip() else "?"
        return f"server FAILED ({stage}): {last} - see {SERVER_LOG.name}"

    try:
        import uvicorn

        from app import app as fastapi_app
    except Exception:
        return log_failure("import")

    failure: list[str] = []

    def run() -> None:
        try:
            uvicorn.run(fastapi_app, host="127.0.0.1", port=cfg["port"],
                        log_level="warning")
        except Exception:
            failure.append(log_failure("runtime"))

    threading.Thread(target=run, name="dc-server", daemon=True).start()

    # Wait until the server answers, but never hang forever.
    for _ in range(50):
        if failure:
            return failure[0]
        if port_in_use(cfg["port"]):
            return "internal server running"
        time.sleep(0.1)
    return failure[0] if failure else "server did not answer within 5s"


def enable_dark_titlebar(window) -> None:
    """Windows only: dark title bar via DWM. Silently a no-op elsewhere."""
    if sys.platform != "win32":
        return
    try:
        import ctypes

        DWMWA_USE_IMMERSIVE_DARK_MODE = 20
        value = ctypes.c_int(1)
        ctypes.windll.dwmapi.DwmSetWindowAttribute(
            int(window.winId()), DWMWA_USE_IMMERSIVE_DARK_MODE,
            ctypes.byref(value), ctypes.sizeof(value))
    except Exception:
        pass


def main() -> int:
    cfg = load_config()
    note = start_server(cfg)

    from PySide6.QtCore import Qt, QUrl
    from PySide6.QtGui import QAction, QColor, QDesktopServices, QIcon, QPalette
    from PySide6.QtWebEngineWidgets import QWebEngineView
    from PySide6.QtWidgets import (
        QApplication,
        QDialog,
        QDialogButtonBox,
        QFileDialog,
        QFormLayout,
        QHBoxLayout,
        QLineEdit,
        QMainWindow,
        QMessageBox,
        QPushButton,
        QSpinBox,
        QStyleFactory,
        QToolBar,
        QWidget,
    )

    base_url = f"http://127.0.0.1:{cfg['port']}"

    class SettingsDialog(QDialog):
        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Connection")
            self.setMinimumWidth(560)

            form = QFormLayout(self)
            form.setVerticalSpacing(12)
            form.setContentsMargins(18, 18, 18, 18)

            self.path_edit = QLineEdit(cfg["stats_path"])
            self.path_edit.setPlaceholderText(
                "empty = auto-detect (Documents\\...\\Osiris Data)")
            browse = QPushButton("Browse...")
            browse.clicked.connect(self._browse)
            row = QHBoxLayout()
            row.addWidget(self.path_edit)
            row.addWidget(browse)
            form.addRow("Stats file:", row)

            self.port_spin = QSpinBox()
            self.port_spin.setRange(1024, 65535)
            self.port_spin.setValue(cfg["port"])
            form.addRow("Port:", self.port_spin)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Save
                | QDialogButtonBox.StandardButton.Cancel)
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            form.addRow(buttons)

        def _browse(self) -> None:
            path, _ = QFileDialog.getOpenFileName(
                self, "Pick DamageCounter_Stats.json",
                self.path_edit.text() or str(Path.home()),
                "JSON (*.json)")
            if path:
                self.path_edit.setText(path)

    class MainWindow(QMainWindow):
        def __init__(self) -> None:
            super().__init__()
            self.setWindowTitle("DamageCounter")
            self.resize(1280, 860)

            self.view = QWebEngineView()
            # Chromium paints white until the page loads: force the page
            # background to the theme color so there is never a white flash.
            self.view.page().setBackgroundColor(QColor(COLORS["bg"]))
            self.setCentralWidget(self.view)

            bar = QToolBar("Navigation")
            bar.setMovable(False)
            bar.setContextMenuPolicy(Qt.ContextMenuPolicy.PreventContextMenu)
            self.addToolBar(bar)

            def nav_action(label: str, path: str) -> QAction:
                act = QAction(label, self)
                act.triggered.connect(lambda: self.view.load(QUrl(base_url + path)))
                bar.addAction(act)
                return act

            nav_action("Leaderboard", "/")
            nav_action("Spells", "/spells")
            nav_action("Fights", "/fights")
            nav_action("Settings", "/settings")

            reload_act = QAction("Reload", self)
            reload_act.triggered.connect(self.view.reload)
            bar.addAction(reload_act)

            browser_act = QAction("Open in browser", self)
            browser_act.triggered.connect(
                lambda: QDesktopServices.openUrl(QUrl(base_url)))
            bar.addAction(browser_act)

            # Percorso del file e porta restano in un dialogo nativo, non
            # nella pagina Settings: servono proprio quando il server non
            # parte, e in quel caso nessuna pagina sarebbe raggiungibile.
            settings_act = QAction("Connection", self)
            settings_act.triggered.connect(self.open_settings)
            bar.addAction(settings_act)

            self.statusBar().showMessage(f"{note}  •  {base_url}")
            self.view.load(QUrl(base_url))

            if "FAILED" in note or "did not answer" in note:
                QMessageBox.critical(
                    self, "Server error",
                    f"The internal server did not start:\n\n{note}\n\n"
                    f"Full traceback: {SERVER_LOG}")

        def open_settings(self) -> None:
            dlg = SettingsDialog(self)
            enable_dark_titlebar(dlg)
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return
            cfg["stats_path"] = dlg.path_edit.text().strip()
            cfg["port"] = dlg.port_spin.value()
            save_config(cfg)
            QMessageBox.information(
                self, "Settings saved",
                "New settings take effect the next time the app starts.")

    qt_app = QApplication(sys.argv)

    icon_path = BASE_DIR / "icon.png"
    if icon_path.exists():
        qt_app.setWindowIcon(QIcon(str(icon_path)))

    # Fusion e' l'unico stile Qt che rispetta davvero una palette custom;
    # quello di default su Windows ignora meta' dei colori (l'effetto "1995").
    qt_app.setStyle(QStyleFactory.create("Fusion"))
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor(COLORS["bg"]))
    palette.setColor(QPalette.ColorRole.WindowText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Base, QColor(COLORS["panel"]))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor(COLORS["panel2"]))
    palette.setColor(QPalette.ColorRole.Text, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Button, QColor(COLORS["panel2"]))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Highlight, QColor(COLORS["accent"]))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor(COLORS["bg"]))
    palette.setColor(QPalette.ColorRole.ToolTipBase, QColor(COLORS["panel2"]))
    palette.setColor(QPalette.ColorRole.ToolTipText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.PlaceholderText, QColor(COLORS["muted"]))
    qt_app.setPalette(palette)
    qt_app.setStyleSheet(QSS)

    window = MainWindow()
    enable_dark_titlebar(window)
    window.show()
    return qt_app.exec()


if __name__ == "__main__":
    sys.exit(main())
