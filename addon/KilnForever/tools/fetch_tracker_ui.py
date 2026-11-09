"""Fetch checksum-pinned Forever tracker source for integration regressions."""

import hashlib
import urllib.request
from pathlib import Path

REVISION = "b401e0332adfbf0460d319b06d8ea29279a941f1"
FILES = {
    "Blizzard_ObjectiveTrackerModule.lua": "605b9be7f2aef1628692ddabafaf3256bb08943500c0e61f1eb5ac2d0c332cdb",
    "Blizzard_ObjectiveTrackerBlock.lua": "29312dc4ed67640ed3a1f928d5fef0a5c8614b03371cd08370bcd495262fa7c1",
    "Blizzard_ObjectiveTrackerAnimTemplates.lua": "463c2ac934a7d76451be662a74703573656b415ec93dbe316105dd314af2f9dd",
}


def main():
    root = Path("tools/.cache/tracker-ui")
    root.mkdir(parents=True, exist_ok=True)
    for name, expected in FILES.items():
        path = root / name
        if not path.exists():
            url = f"https://raw.githubusercontent.com/Gethe/wow-ui-source/{REVISION}/Interface/AddOns/Blizzard_ObjectiveTracker/{name}"
            data = urllib.request.urlopen(url, timeout=30).read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError(f"Tracker source checksum mismatch: {name}")
            path.write_bytes(data)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Tracker source checksum mismatch: {name}")


if __name__ == "__main__":
    main()
