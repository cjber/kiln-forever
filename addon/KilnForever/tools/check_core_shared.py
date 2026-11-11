"""Check this addon's copy of Forever Core's development tooling against cjber/forever-core main.

Forever Core is the source of every file in VENDORED, this script included: core's tools/sync_consumers.py copies
them into each consumer and core's tools/check_consumers.py reads the same map. Run it from a consumer's root, whose
repository is inferred from its Git origin:

    python3 tools/check_core_shared.py             every file this repo vendors must match core main
    python3 tools/check_core_shared.py --base REF  only the vendored files that REF...HEAD changes

A consumer whose addon lives below its repo root, beside a non-addon project, keeps every vendored file under the
folder CONSUMER_ROOT names for it. Kiln Forever's CI therefore runs this script from the repository root with
`python3 addon/KilnForever/tools/check_core_shared.py`, and it still finds `addon/KilnForever/<core path>`.

Only development tooling is copied now: the runtime files are ForeverCore's alone, and an addon requires it with
`## Dependencies: ForeverCore`. The `--base` form runs on pull requests: a PR that edits a vendored copy by hand fails,
while a consumer that only lags behind core does not block unrelated work. The full form runs on a schedule and reports
the lag.
"""

import argparse
import hashlib
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

# A consumer with its addon below its repo root keeps each vendored file at `<folder>/<core path>`. Every other
# consumer mirrors core's paths from its repository root.
CONSUMER_ROOT = {"kiln-forever": "addon/KilnForever"}

KILN_CONSUMERS = ("kiln-forever",)
# The project rules reach every published addon in the suite.
SUITE_CONSUMERS = (
    "adventure-guide-forever",
    "legacy-forever",
    "shortest-path-forever",
    "skillup-forever",
    "tweaks-forever",
    "field-guide-forever",
    "commissions-forever",
    "macro-assist-forever",
)
# The dead-code gate also goes to Macro Assist, which has no settings page, and not to Commissions, which has none.
DEADCODE_CONSUMERS = (
    "adventure-guide-forever",
    "legacy-forever",
    "shortest-path-forever",
    "skillup-forever",
    "tweaks-forever",
    "field-guide-forever",
    "macro-assist-forever",
)
# Kiln Forever runs the checker from its own CI, so it takes the checker but not the reusable workflow.
CHECKER_CONSUMERS = SUITE_CONSUMERS + KILN_CONSUMERS

# Consumer path: the repos that carry it. A consumer keeps each file at the same path as core, except where SOURCES
# names the core file it is copied from.
VENDORED = {
    "tools/check_core_shared.py": CHECKER_CONSUMERS,
    "tools/check_client_load.py": SUITE_CONSUMERS,
    "tools/blizzard_fonts.txt": SUITE_CONSUMERS,
    "tools/check_menu_scroll.py": SUITE_CONSUMERS,
    "tools/check_copy.py": SUITE_CONSUMERS,
    ".github/workflows/core-shared-drift.yml": SUITE_CONSUMERS,
    "tools/deadcode.py": DEADCODE_CONSUMERS,
    "tools/deadcode-allow.txt": DEADCODE_CONSUMERS,
    # The store page's button row (wow-forever-addon/store-page.md), identical on every page.
    "docs/discord-button.png": SUITE_CONSUMERS,
    "docs/github-sponsors-button.png": SUITE_CONSUMERS,
    "docs/kofi-button.png": SUITE_CONSUMERS,
}
# Core keeps the consumers' workflow out of its own .github/workflows, where it would run against core itself.
SOURCES = {
    ".github/workflows/core-shared-drift.yml": "tools/core-shared-drift.yml",
    "tools/check_copy.py": ".agents/skills/wow-forever-addon/check_copy.py",
}

# Every repository this map governs, prefixed consumers included.
KNOWN_CONSUMERS = frozenset(repo for consumers in VENDORED.values() for repo in consumers)


def source(path):
    """The path in forever-core that the consumer's `path` is copied from."""
    return SOURCES.get(path, path)


def consumer_path(repo, path):
    """Where `repo` keeps the vendored `path`, relative to that consumer repo's root."""
    folder = CONSUMER_ROOT.get(repo)
    return f"{folder}/{path}" if folder else path


def paths_for(repo):
    return [path for path, consumers in VENDORED.items() if repo in consumers]


def repo_from_git():
    """Return the GitHub repo name, independent of the checkout directory or worktree name."""
    result = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, check=False)
    if result.returncode:
        return None
    remote = result.stdout.strip()
    if remote.startswith("git@github.com:"):
        name = remote.removeprefix("git@github.com:")
    else:
        parsed = urlparse(remote)
        if parsed.hostname != "github.com":
            return None
        name = parsed.path.lstrip("/")
    name = name.strip("/")
    if name.lower().endswith(".git"):
        name = name[:-4]
    owner, separator, repo = name.partition("/")
    repo = repo.lower()
    return repo if separator and owner.lower() == "cjber" and repo in KNOWN_CONSUMERS else None


def changed_since(base):
    """Every path that `base...HEAD` adds, changes, renames or deletes."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", f"{base}...HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise SystemExit(f"git diff {base}...HEAD failed: {result.stderr.strip()}")
    return set(result.stdout.split())


def core_main(path):
    url = f"https://raw.githubusercontent.com/cjber/forever-core/main/{source(path)}"
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def compare(root, repo, paths, fetch=core_main):
    failures = []
    for path in paths:
        display = consumer_path(repo, path)
        try:
            expected = fetch(path)
        except (OSError, urllib.error.URLError, TimeoutError) as error:
            failures.append(f"{display}: could not read core main: {error}")
            continue
        target = root / display
        if not target.is_file():
            failures.append(f"{display}: missing here, core {hashlib.sha256(expected).hexdigest()[:12]}")
            continue
        actual = target.read_bytes()
        if actual != expected:
            failures.append(
                f"{display}: consumer {hashlib.sha256(actual).hexdigest()[:12]} "
                f"core {hashlib.sha256(expected).hexdigest()[:12]}"
            )
    return failures


def main(argv=None, fetch=core_main):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", help="check only the vendored files that BASE...HEAD changes")
    parser.add_argument("--repo", help="this consumer's repo name (default: infer it from Git origin)")
    arguments = parser.parse_args(argv)

    root = Path.cwd()
    if arguments.repo and arguments.repo not in KNOWN_CONSUMERS:
        raise SystemExit(f"Unknown consumer repo: {arguments.repo}")
    repo = arguments.repo or repo_from_git()
    if repo is None:
        raise SystemExit("Cannot identify a known cjber consumer from git remote; pass --repo explicitly.")
    paths = paths_for(repo)
    if arguments.base:
        touched = changed_since(arguments.base)
        paths = [path for path in paths if consumer_path(repo, path) in touched]
        if not paths:
            print(f"No vendored file changed since {arguments.base}.")
            return 0
    failures = compare(root, repo, paths, fetch)
    if failures:
        print("Vendored files differ from forever-core main:\n  " + "\n  ".join(failures))
        print("Change the file in cjber/forever-core, then copy it here with its tools/sync_consumers.py.")
        return 1
    print(f"{len(paths)} vendored files match forever-core main.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
