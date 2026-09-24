#!/bin/zsh
# Baut die Website und lädt sie auf depflush.com (ALL-INKL, SSH-Key nötig)
set -e
cd "$(dirname "$0")"
python3 build.py
rsync -avz --delete public/ ssh-w01c290d@w01c290d.kasserver.com:/www/htdocs/w01c290d/depflush.com/
echo "✓ https://depflush.com"
