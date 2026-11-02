#!/usr/bin/env python3
import plistlib
import re
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
version = sys.argv[1]
if not re.fullmatch(r'4\.2\.1(?:\+[1-9][0-9]*)?', version):
    raise SystemExit('unsupported modification version')
f = root / 'Makefile'
f.write_text(re.sub(r'^export PACKAGE_VERSION := .+$', 'export PACKAGE_VERSION := ' + version,
                    f.read_text(), count=1, flags=re.M))
f = root / 'layout/DEBIAN/control'
f.write_text(re.sub(r'^Version: .+$', 'Version: ' + version, f.read_text(), count=1, flags=re.M))
for name in ('TVZPrefs', 'CCTouchViz'):
    f = root / name / 'Resources/Info.plist'
    info = plistlib.loads(f.read_bytes())
    info['CFBundleVersion'] = version
    info['CFBundleShortVersionString'] = '4.2.1'
    f.write_bytes(plistlib.dumps(info, sort_keys=False))
print('Synchronized version:', version)
