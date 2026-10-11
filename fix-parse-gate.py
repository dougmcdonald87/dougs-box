"""Mechanical repairs across the built repo:
(a) reorder Set-StrictMode/param blocks (param must come first for PS 5.1 parse),
(b) replace 1GiB literals with dot-sourced $OneGiB variable; add definition to common.ps1.
Then report what it touched."""
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])

# ---- (a) reorder: find first Set-StrictMode statement followed by a param block
swapped = []
setsm = re.compile(r"(?m)^Set-StrictMode -Version Latest\s*$")
param_re = re.compile(r"(?m)^param\s*\(")

for p in root.rglob("*.ps1"):
    if "tests" in p.parts or p.name.startswith("_"):
        continue
    if p.name == "common.ps1":
        continue
    text = p.read_text(encoding="utf-8-sig")
    m1 = setsm.search(text)
    if not m1:
        continue
    mp = param_re.search(text)
    if not mp or mp.end() < m1.end():
        continue
    # find the closing paren of param block, brace-matched from param (
    open_paren = text.find("(", mp.start())
    depth, i = 1, open_paren + 1
    while i < len(text) and depth > 0:
        c = text[i]
        if c == "(": depth += 1
        elif c == ")": depth -= 1
        i += 1
    param_block_end = i  # index just past ')'
    # swallow trailing newline after the block
    while param_block_end < len(text) and text[param_block_end] in "\\r\\n":
        param_block_end += 1
    setsm_line_end = text.find("\n", m1.start()) + 1
    strict_line = text[m1.start():setsm_line_end]
    param_block = text[mp.start():param_block_end]
    before = text[:m1.start()]
    param_block_clean = re.sub(r"^param\s*\(\s*$", "param (", param_block)
    rebuilt = before + param_block_clean.rstrip() + "\n" + strict_line + text[param_block_end:]
    p.write_text(rebuilt, encoding="utf-8")
    swapped.append(str(p.relative_to(root)))

print(" reordered param-after-strictmode in:")
for s in swapped: print("   ", s)

# ---- (b) 1GiB -> $OneGiB plus definition in common.ps1
replaced = []
one_re = re.compile(r"(?<![\w$])1GiB(?![\w$])")
for p in root.rglob("*.ps1"):
    text = p.read_text(encoding="utf-8-sig")
    if "1GiB" in text:
        t = one_re.sub("$OneGiB", text)
        p.write_text(t, encoding="utf-8")
        replaced.append(str(p.relative_to(root)))

common = root / "scripts" / "common.ps1"
ct = common.read_text(encoding="utf-8-sig")
if "$OneGiB" not in ct:
    anchor = "Set-StrictMode -Version Latest\n"
    ct = ct.replace(anchor, anchor + "\n# canonical binary-GiB constant (a 5.1-safe literal, dot-source spread)\n$OneGiB = 1073741824.0\n", 1)
    common.write_text(ct, encoding="utf-8")
    print(" common.ps1: $OneGiB definition added")

print(" 1GiB replaced in:")
for s in replaced: print("   ", s)
print(" DONE. re-run static gate.")
