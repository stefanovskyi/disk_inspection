#!/usr/bin/env python3
"""Build the self-contained interactive concept from exported native geometry."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
directory = root / "docs/prototypes/chart-styles"
data = json.loads((directory / "space-scenes.json").read_text())
template = (directory / "space-preview.template.html").read_text()
html = template.replace("__SPACE_SCENES__", json.dumps(data, separators=(",", ":")))
(directory / "index.html").write_text(html)
print(directory / "index.html")
