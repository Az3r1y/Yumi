#!/usr/bin/env python3
"""Writes translations into the String Catalog.

usage: strings-apply.py en.json [fr-overrides.json]
en.json maps a key (the French written in the code) to its English. fr-overrides.json gives the
French shown for a key that is not French itself (the developer panels, written in English).
"""
import json, re, sys
path = 'Yumi/Sources/App/Localization/Localizable.xcstrings'
catalog = json.load(open(path))
english = {}
for f in sys.argv[1].split(','):
    english.update(json.load(open(f)))
french = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}

def positional(text):
    """%@ %lld … numbered in order, so that a translation may move them."""
    n = 0
    def number(m):
        nonlocal n
        if m.group(0) == '%%':
            return '%%'
        n += 1
        return f'%{n}${m.group(1)}'
    return re.sub(r'%%|%(@|lld|ld|d|f|\.\df)', number, text)

def spec_count(text):
    return len(re.findall(r'%(?!%)(?:\d+\$)?(?:@|lld|ld|d|f|\.\df)', text))

missing = []
for key, entry in catalog['strings'].items():
    if entry.get('extractionState') == 'stale':
        continue
    locs = entry.setdefault('localizations', {})
    if key in french:
        value = french[key]
        if spec_count(key) > 1 and '$' not in value: value = positional(value)
        locs['fr'] = {'stringUnit': {'state': 'translated', 'value': value}}
    if key in english:
        value = english[key]
        if spec_count(key) != spec_count(value):
            sys.exit(f'specifiers differ: {key!r} -> {value!r}')
        if spec_count(key) > 1 and '$' not in value: value = positional(value)
        locs['en'] = {'stringUnit': {'state': 'translated', 'value': value}}
    elif 'en' not in locs:
        missing.append(key)
json.dump(catalog, open(path, 'w'), ensure_ascii=False, indent=2, sort_keys=True)
open(path, 'a').write('\n')
print(f'{len(missing)} keys without English', *missing[:40], sep='\n')
