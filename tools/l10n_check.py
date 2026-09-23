#!/usr/bin/env python3
"""Prüft, ob alle L("...")-Texte eine Übersetzung in Sources/Strings.swift haben."""
import re, glob, os
os.chdir(os.path.join(os.path.dirname(__file__), '..'))
keys = []
for f in sorted(glob.glob('Sources/*.swift')):
    if f.endswith('Strings.swift'): continue
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"', open(f).read()):
        if m.group(1) not in keys: keys.append(m.group(1))
known = set(re.findall(r'^    "((?:[^"\\]|\\.)*)": \[', open('Sources/Strings.swift').read(), re.M))
missing = [k for k in keys if k not in known]
print(f"{len(keys)} Texte, {len(missing)} ohne Übersetzung")
for k in missing: print("  -", k)
