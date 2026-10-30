from __future__ import annotations

import sys
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
PARENT_ROOT = PLUGIN_ROOT.parent


def _find_workspace_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "astrbot").is_dir() and (
            candidate / "pyproject.toml"
        ).is_file():
            return candidate
    raise RuntimeError("Unable to locate AstrBot workspace root from test path.")


WORKSPACE_ROOT = _find_workspace_root(PLUGIN_ROOT)
ORIGINAL_SYS_PATH = list(sys.path)

for path in (WORKSPACE_ROOT, PARENT_ROOT):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)


def pytest_sessionfinish(session, exitstatus):
    sys.path[:] = ORIGINAL_SYS_PATH
