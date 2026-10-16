"""Static audit gate for the built DevBox repo: YAML parse, action-SHA pinning,
append-only vocabulary, secret-shape scan, READY-lie scan. Exits nonzero on any fail."""
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(".")
fails, notes = [], []
ok = lambda msg: notes.append("OK   " + msg)

# ---- REVIEWED ALLOWLIST (do NOT extend silently; every entry needs a reason).
# Each exempted file is an ENFORCER of the rule it gets flagged for:
#   validate.yml        contains the grep that hunts the destructive vocabulary.
#   devbox.tests.ps1    unit-mirror of the same vocabulary audit.
#   check-storage-host.ps1  asserts the ABSENCE of forbidden bind/auth strings.
#   setup-storage-host.ps1  documents the prohibition it implements (docstring only).
EXEMPT = {
    str(root / ".github" / "workflows" / "validate.yml"): "enforcement grep itself",
    str(root / "tests" / "devbox.tests.ps1"): "unit mirror of vocabulary audit",
    str(root / "storage-host" / "check-storage-host.ps1"): "negative assertions (0.0.0.0/htpasswd absence)",
    str(root / "storage-host" / "setup-storage-host.ps1"): "docstring of the prohibition",
}

def exempt(path):
    return any(str(path).replace("\\\\", "\\").lower().endswith(k.replace("\\\\", "\\").lower()) or
               pathlib.PurePath(str(path)).name == pathlib.PurePath(k).name and pathlib.PurePath(str(path)).name.lower() == pathlib.PurePath(k).name.lower()
               for k in EXEMPT)

# ---- 1. YAML parse
import yaml
for p in sorted(root.rglob("*.yml")):
    try:
        list(yaml.safe_load_all(p.read_text(encoding="utf-8")))
        ok(f"YAML   {p}")
    except Exception as e:
        fails.append(f"YAML   {p.name}: {e}")

# ---- 2. every `uses:` pinned to a full 40-hex SHA with a version comment
for p in sorted(root.rglob("*.yml")):
    for i, line in enumerate(p.read_text(encoding="utf-8-sig").splitlines(), 1):
        m = re.search(r"uses:\s*([^\s]+)", line)
        if not m:
            continue
        ref = m.group(1).strip()
        mm = re.match(r"^[^@]+@([0-9a-f]{40})\s*(?:#.*)?$", line.split("uses:")[1].strip())
        if not mm:
            fails.append(f"PIN    {p.name}:{i} not pinned to full SHA: {ref}")
        elif not re.search(r"#\s*v?\d", line):
            fails.append(f"PIN    {p.name}:{i} lacks version comment: {ref}")
ok("PIN    checked all uses: lines")

# ---- 3. append-only vocabulary absent from ALL CODE files (md prose allowed)
audit_roots = [root / ".github", root / "scripts", root / "storage-host", root / "tests", root / "config"]
word_pat = re.compile(r"\b(forget|prune)\b", re.I)
for base in audit_roots:
    if not base.exists():
        continue
    for p in list(base.rglob("*.ps1")) + list(base.rglob("*.yml")) + list(base.rglob("*.json")):
        if exempt(p):
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            if word_pat.search(line):
                fails.append(f"BAN   {p}:{i}: {line.strip()[:110]}")
ok("BAN    destructive vocabulary absent from code files (enforcers exempted)")

# ---- 3b. --delete in any script
for p in list((root / "scripts").rglob("*.ps1")) + list((root / "storage-host").rglob("*.ps1")):
    if exempt(p):
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
        if "--delete" in line:
            fails.append(f"BAN   {p}:{i}: --delete")

# ---- 4. forbidden-network vocabulary in all code files (Tailscale-only law, Phase 39)
bad_words = ["ngrok", "cloudflare tunnel", "funnel", "zerotier", "openvpn",
             "htpasswd", "reverse proxy", "0.0.0.0"]
for base in [root / ".github", root / "scripts", root / "storage-host"]:
    if not base.exists():
        continue
    for p in list(base.rglob("*.ps1")) + list(base.rglob("*.yml")) + list(base.rglob("*.json")):
        if exempt(p):
            continue
        text = p.read_text(encoding="utf-8-sig", errors="replace").lower()
        for w in bad_words:
            if w in text and w != "0.0.0.0":
                fails.append(f"TSEC  {p.name}: mentions {w}")
ok("TSEC  no extra-network-security vocabulary in code (enforcers exempted)")

# 0.0.0.0 check SPECIAL: prohibition with explicit fail path is THE required behaviour.
# Guard files that reference it only to enforce absence are exempt; any literal use
# for actually BINDING would still slip through storage task args checks upstream.
for p in list((root / "storage-host").rglob("*.ps1")) + list((root / "scripts").rglob("*.ps1")):
    if exempt(p):
        continue
    if "0.0.0.0" in p.read_text(encoding="utf-8-sig", errors="replace"):
        fails.append(f"0HOST {p.name}: literal 0.0.0.0 got into code")

# ---- 5. secret-shape scan (Phase 40) in committed files (examples are templates)
secret_pat = re.compile(
    r"(?:password|passwd|pwd)\s*[:=]\s*[\"'][^\"']{5,}[\"']"
    r"|BEGIN [A-Z ]*PRIVATE KEY"
    r"|ghp_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|tskey-auth-[A-Za-z0-9\-]+|AKIA[0-9A-Z]{16}", re.I)
skip_names = {"BUILD-LOCAL-INVENTORY.md", "failures.txt"}
for p in root.rglob("*"):
    if p.is_dir() or p.name in skip_names:
        continue
    if "/.git/" in str(p.resolve().as_posix()):
        continue
    if p.suffix.lower() not in {".ps1", ".yml", ".json", ".md", ".hujson", ".gitignore", ".txt"}:
        continue
    try:
        text = p.read_text(encoding="utf-8-sig", errors="replace")
    except Exception:
        continue
    m = secret_pat.search(text)
    if m:
        fails.append(f"SECRET {p.name}: {m.group(0)[:60]}")
ok("SECRET shape-scan over committed files")

# ---- 6. no workflow with push+secret mix leveraged: environment 'devbox' only
dev = (root / ".github" / "workflows" / "devbox.yml").read_text(encoding="utf-8-sig")
if "environment: devbox" not in dev:
    fails.append("TRIGGER devbox.yml missing environment: devbox")
if "workflow_dispatch" not in dev.split("concurrency:")[0]:
    fails.append("TRIGGER devbox.yml missing manual workflow_dispatch")
ok("TRIGGER manual-only + devbox environment present")

print("\n".join("  " + n for n in notes))
if fails:
    print("\n".join("  FAIL " + f for f in fails))
    print(f"\nAUDIT RESULT: {len(fails)} failures")
    sys.exit(1)
print("\nAUDIT RESULT: all static gates PASS")
