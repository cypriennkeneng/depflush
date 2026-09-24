#!/usr/bin/env python3
"""Baut die statische Website nach website/public/.

- src/index.html ist die Quelle (dieselbe Datei wie die Claude-Vorschau)
- Google Fonts werden heruntergeladen und lokal ausgeliefert (DSGVO: keine Verbindung zu Google)
- Download-Links zeigen auf GitHub Releases
- Dateien aus static/ (.htaccess, robots.txt, sitemap.xml) werden mitkopiert
- Favicon aus ../Resources/icon_1024.png

Aufruf:  python3 website/build.py
"""
import os, re, shutil, subprocess, glob

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "src", "index.html")
OUT = os.path.join(HERE, "public")
# Ko-fi-/Buy-Me-a-Coffee-Seite – hier eintragen, z. B. "https://ko-fi.com/depflush"
SUPPORT_URL = "https://ko-fi.com/depflush"

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

def curl(url, dest=None):
    cmd = ["curl", "-fsSL", "-A", UA, url]
    if dest:
        subprocess.run(cmd + ["-o", dest], check=True)
        return None
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

def main():
    src = open(SRC, encoding="utf-8").read()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, "fonts"))

    # 1. Schriften lokal
    m = re.search(r'<link rel="stylesheet" href="(https://fonts\.googleapis\.com/[^"]+)">', src)
    if m:
        css = curl(m.group(1).replace("&amp;", "&"))
        def grab(mm):
            url = mm.group(1)
            name = re.sub(r"[^A-Za-z0-9._-]", "_", url.split("/")[-1])
            fam = re.sub(r"[^a-z0-9]", "", url.split("/s/")[1].split("/")[0]) if "/s/" in url else "font"
            fname = f"{fam}-{name}"
            path = os.path.join(OUT, "fonts", fname)
            if not os.path.exists(path):
                curl(url, path)
            return f"url(./{fname})"
        css = re.sub(r"url\((https://fonts\.gstatic\.com/[^)]+)\)", grab, css)
        open(os.path.join(OUT, "fonts", "fonts.css"), "w").write(css)
        src = re.sub(r'\s*<link rel="preconnect"[^>]*>', "", src)
        src = src.replace(m.group(0), '<link rel="stylesheet" href="fonts/fonts.css">')

    # 2. Download: Links zeigen auf GitHub Releases

    # 2b. Spendenlink
    if SUPPORT_URL:
        src = src.replace('href="https://ko-fi.com/"', f'href="{SUPPORT_URL}"')
    else:
        print("Hinweis: SUPPORT_URL ist leer – der Spendenbutton zeigt auf ko-fi.com")

    # 3. Favicon
    icon = os.path.join(ROOT, "Resources", "icon_1024.png")
    if os.path.exists(icon):
        for size, fname in ((64, "favicon.png"), (180, "apple-touch-icon.png"), (512, "og-icon.png")):
            subprocess.run(["sips", "-z", str(size), str(size), icon, "--out", os.path.join(OUT, fname)],
                           check=False, capture_output=True)

    # 3b. Statische Dateien (.htaccess, robots.txt, sitemap.xml)
    static_dir = os.path.join(HERE, "static")
    if os.path.isdir(static_dir):
        for name in os.listdir(static_dir):
            shutil.copy2(os.path.join(static_dir, name), os.path.join(OUT, name))

    # 4. Vollständiges Dokument
    split = src.index("<header")
    head, body = src[:split], src[split:]
    extra = ('<link rel="icon" type="image/png" href="favicon.png">\n'
             '<link rel="apple-touch-icon" href="apple-touch-icon.png">\n'
             '<meta property="og:title" content="Depflush">\n'
             '<meta property="og:description" content="Free Mac app that finds the gigabytes development leaves behind.">\n'
             '<meta property="og:image" content="https://depflush.com/og-icon.png">\n')
    html = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            + extra + head + "</head>\n<body>\n" + body + "\n</body>\n</html>\n")
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(html)
    print("OK →", OUT)

if __name__ == "__main__":
    main()
