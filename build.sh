#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$#" -le 1 ] && [ "${1:-roothide}" = roothide ] || {
    echo 'This checkout packages roothide only.' >&2; exit 2;
}
[ -n "${THEOS:-}" ] || { echo 'THEOS is required' >&2; exit 2; }
export THEOS_PACKAGE_SCHEME=roothide
python3 -m unittest discover -s tests -v
make clean
make package FINALPACKAGE=1
