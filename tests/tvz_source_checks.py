"""Small source checks for generated projects; these are not an ObjC compiler."""

import re
from pathlib import Path

# Preserve literals and line numbers; comment-looking text inside strings is data.
_PARTS = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/')


def strip_comments(text):
    def replace(match):
        value = match.group()
        if value.startswith(('//', '/*')):
            return ''.join('\n' if ch == '\n' else ' ' for ch in value)
        return value
    return _PARTS.sub(replace, text)


def mask_literals(text):
    """Keep positions while removing strings that could imitate active code."""
    return _PARTS.sub(lambda match: ''.join('\n' if ch == '\n' else ' '
                                           for ch in match.group()), text)


def function_body(source, name):
    """Find a definition, excluding mere declarations and call sites."""
    text = strip_comments(source)
    match = re.search(r'\b' + re.escape(name) + r'\s*\([^;{}]*\)\s*\{', mask_literals(text))
    if not match:
        return None
    start, depth = match.end(), 1
    token = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]')
    for part in token.finditer(text, start):
        if part.group() == '{':
            depth += 1
        elif part.group() == '}':
            depth -= 1
            if not depth:
                return text[start:part.start()]
    return None


def dependency_names(value):
    """Dependencies required on every alternative, not substring matches."""
    required = set()
    for group in value.split(','):
        alternatives = []
        for term in group.split('|'):
            match = re.fullmatch(r'\s*([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)?\s*(?:\([^()]+\))?\s*', term)
            if not match:
                raise ValueError('Invalid dependency: ' + term)
            alternatives.append(match.group(1))
        if len(set(alternatives)) == 1:
            required.add(alternatives[0])
    return required


def check_sources(project, meta):
    """Return actionable static errors; never claim to establish behavior."""
    project = Path(project)
    prefix, symbol = meta['class_prefix'], meta['symbol_prefix']
    errors = []
    paths_file = project/'Sources'/(prefix + 'Paths.h')
    hook_file = project/'Hooks'/(prefix + 'Main.xm')
    try:
        paths = paths_file.read_text(encoding='utf-8')
        hook = strip_comments(hook_file.read_text(encoding='utf-8'))
    except (OSError, UnicodeError) as error:
        return [str(error)]
    active_hook = mask_literals(hook)
    body = function_body(paths, symbol + '_preferencesPath')
    expected = '@"/var/mobile/Library/Preferences/' + meta['package'] + '.plist"'
    if body is None or not re.fullmatch(r'\s*return\s+' + re.escape(expected) + r'\s*;\s*', body):
        errors.append('preferencesPath must directly return the real mobile user plist path in every scheme')
    if not re.search(r'%hook\s+[A-Za-z_]\w*\b|\bMSHookMessageEx\s*\(', active_hook):
        errors.append('Main.xm has no active Logos or runtime hook')
    # The shipped core example is a SpringBoard hook. For custom bundles it must
    # be replaced together with the injection filter, before source gates pass.
    if meta.get('bundle') != 'com.apple.springboard' and re.search(r'%hook\s+SpringBoard\b', active_hook):
        errors.append('Replace the sample SpringBoard hook for the custom target bundle')
    if not re.search(r'\b' + re.escape(symbol) + r'_isEnabled\b', active_hook):
        errors.append('Main.xm does not actively read the enabled state')
    if not re.search(r'addObserverForName\s*:\s*' + re.escape(prefix) + r'PreferencesChanged\b', active_hook):
        errors.append('Main.xm does not register the configuration refresh observer')
    if not re.search(r'^\s*#\s*import\s+"' + re.escape(prefix) + r'Preferences\.h"', hook, re.M):
        errors.append('Main.xm uses preferences but lacks its Preferences.h import')
    if 'scheme' in meta:
        try:
            build = (project/'build.sh').read_text(encoding='utf-8')
            if not re.search(r'^DEFAULT_SCHEME=' + re.escape(meta['scheme']) + r'\s*$', build, re.M):
                errors.append('build.sh default scheme differs from tweak.json')
            if meta.get('github_actions'):
                workflow = (project/'.github/workflows/build.yml').read_text(encoding='utf-8')
                variants = re.findall(r'^\s*-\s+build_variant:\s*(\S+)', workflow, re.M)
                if variants != [meta['scheme']]:
                    errors.append('CI matrix must contain only the manifest scheme')
                for option in ('--project .', '--scheme', '--expected-version'):
                    if option not in workflow:
                        errors.append('CI artifact gate is missing ' + option)
        except (OSError, UnicodeError, TypeError) as error:
            errors.append('Cannot read build configuration: ' + str(error))
    return errors
