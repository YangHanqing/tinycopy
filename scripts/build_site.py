#!/usr/bin/env python3
"""Sync the static GitHub Pages assets. Python standard library only."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site'
ASSETS = SITE / 'assets'
ASSETS.mkdir(parents=True, exist_ok=True)
for name in ('overview', 'overview-dark', 'history', 'smart-actions', 'translation', 'image-text', 'qrcode', 'settings'):
    shutil.copy2(ROOT / 'assets' / 'screenshots' / f'{name}.png', ASSETS / f'{name}.png')
shutil.copy2(ROOT / 'TinyCopy/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png', ASSETS / 'icon.png')
shutil.copy2(ROOT / 'LICENSE', SITE / 'LICENSE')
(SITE / '.nojekyll').touch()
print('GitHub Pages files ready in site/.')
