#!/usr/bin/env python3
"""Static artifact checks, not signature validation or device acceptance."""
import argparse
import json
import plistlib
import re
import struct
import subprocess
import sys
from pathlib import Path
from tvz_deb_core import read_ar, read_tar, parse_control, dependencies, slices


def plist(blob):
    try:
        return plistlib.loads(blob)
    except plistlib.InvalidFileException:
        # Theos may retain an OpenStep filter; macOS plutil is authoritative.
        result = subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', '-'],
                                input=blob, capture_output=True, check=True)
        return plistlib.loads(result.stdout)


def dylib_dependencies(blob):
    endian = '>' if blob[:4] == bytes.fromhex('cafebabe') else '<'
    n = struct.unpack_from(endian + 'I', blob, 4)[0]
    result = []
    for i in range(n):
        cpu, sub, offset, size, align = struct.unpack_from(endian + '5I', blob, 8 + i * 20)
        thin = blob[offset:offset + size]
        byteorder = '<' if thin[:4] == bytes.fromhex('cffaedfe') else '>'
        commands = struct.unpack_from(byteorder + 'I', thin, 16)[0]
        pos = 32
        names = []
        for _ in range(commands):
            cmd, length = struct.unpack_from(byteorder + 'II', thin, pos)
            if cmd in (0xc, 0x80000018, 0x8000001f, 0x80000023):
                start = struct.unpack_from(byteorder + 'I', thin, pos + 8)[0]
                names.append(thin[pos + start:pos + length].split(b'\0')[0].decode())
            pos += length
        result.append(names)
    return result


def validate(path, expected_version):
    ar = read_ar(Path(path).read_bytes())
    assert ar.get('debian-binary') == b'2.0\n', 'invalid debian-binary'
    control_archives = [n for n in ar if n.startswith('control.tar')]
    data_archives = [n for n in ar if n.startswith('data.tar')]
    assert len(control_archives) == len(data_archives) == 1, 'ambiguous archives'
    control = parse_control(read_tar(control_archives[0], ar[control_archives[0]])['control'])
    files = read_tar(data_archives[0], ar[data_archives[0]])
    assert control['package'] == 'com.82flex.touchvis', 'original package identity changed'
    assert control['name'] == 'Touch-Viz', 'original display name changed'
    assert control['version'] == expected_version, 'version mismatch'
    assert control['architecture'] == 'iphoneos-arm64e', 'not a roothide package'
    assert {'roothide', 'mobilesubstrate', 'preferenceloader'} <= dependencies(control['depends']), 'missing dependencies'
    assert not any(n.startswith('var/jb/') for n in files), 'rootless paths in roothide package'
    binaries = {
        'tweak': 'Library/MobileSubstrate/DynamicLibraries/TouchViz.dylib',
        'prefs': 'Library/PreferenceBundles/TVZPrefs.bundle/TVZPrefs',
        'cc': 'Library/ControlCenter/Bundles/CCTouchViz.bundle/CCTouchViz',
    }
    for label, name in binaries.items():
        assert isinstance(files.get(name), bytes), 'missing binary: ' + name
        archs = slices(files[name], kinds=(6, 8))
        links = dylib_dependencies(files[name])
        assert all(any('libroothide.dylib' in d for d in names) for names in links), label + ': missing roothide link'
        assert all(not any(d.startswith('/var/jb/') for d in names) for names in links), label + ': rootless dependency'
        if label == 'tweak':
            assert all(any('libsubstrate.dylib' in d for d in names) for names in links), 'missing hook library'
        print(label + ': ' + ', '.join(archs))
    filter_path = binaries['tweak'].removesuffix('.dylib') + '.plist'
    assert plist(files[filter_path]) == {'Filter': {'Bundles': ['com.apple.springboard']}}, 'filter changed'
    prefs = plist(files['Library/PreferenceBundles/TVZPrefs.bundle/Info.plist'])
    cc = plist(files['Library/ControlCenter/Bundles/CCTouchViz.bundle/Info.plist'])
    assert prefs['CFBundleExecutable'] == 'TVZPrefs'
    assert prefs['CFBundleIdentifier'] == 'com.82flex.touchviz'
    assert prefs['NSPrincipalClass'] == 'TVZRootListController'
    assert cc['CFBundleExecutable'] == 'CCTouchViz'
    for info in (prefs, cc):
        assert info['CFBundleVersion'] == expected_version, 'bundle version mismatch'
    loader = plist(files['Library/PreferenceLoader/Preferences/TVZPrefs/Root.plist'])['entry']
    assert loader['bundle'] == 'TVZPrefs' and loader['detail'] == 'TVZRootListController'
    assert loader['label'] == 'Touch-Viz'
    print('PASS metadata, dependencies, layout, filter, bundle routes and real Mach-O slices')
    print('NOT VERIFIED: cryptographic signature, device injection, photo import or GIF display')
    return control


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('deb')
    parser.add_argument('--expected-version', required=True)
    args = parser.parse_args()
    try:
        validate(args.deb, args.expected_version)
    except Exception as error:
        print('FAIL:', str(error), file=sys.stderr)
        sys.exit(1)
