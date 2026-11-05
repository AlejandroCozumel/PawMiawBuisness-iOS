#!/usr/bin/env python3
"""Lucide icons for PawMiaw Business, the web's icon set (lucide-react, ISC).

Writes one template image set per icon into Assets.xcassets/Lucide from the
web repo's lucide-react package, and Design/GlyphNames.swift: the SF Symbol →
Lucide map `Glyph` draws with. Icons = every Lucide icon the web imports, plus
every map target. Run from the repo root:

    python3 scripts/lucide-icons.py ../pawmiaw-web
"""
import json, os, re, shutil, sys

WEB = sys.argv[1] if len(sys.argv) > 1 else '../pawmiaw-web'
LUCIDE = os.path.join(WEB, 'node_modules/lucide-react/dist/esm')
ASSETS = 'PawMiawNegocios/Assets.xcassets/Lucide'
SWIFT = 'PawMiawNegocios/Design/GlyphNames.swift'

# SF Symbol (without ".fill") → Lucide name. The screens keep naming SF Symbols;
# `Glyph` draws the Lucide icon when there is one, as the web does.
SF = {
    'plus': 'plus', 'minus': 'minus', 'pencil': 'pencil', 'pencil.line': 'pencil-line', 'square.and.pencil': 'square-pen',
    'chevron.right': 'chevron-right', 'chevron.left': 'chevron-left', 'chevron.down': 'chevron-down', 'chevron.up': 'chevron-up',
    'chevron.up.chevron.down': 'chevrons-up-down', 'person': 'user', 'person.2': 'users', 'person.3': 'users', 'person.3.sequence': 'users',
    'person.crop.circle': 'circle-user', 'person.badge.plus': 'user-plus', 'person.badge.key': 'key-round', 'person.text.rectangle': 'contact',
    'person.crop.circle.badge.checkmark': 'user-check', 'person.badge.shield.checkmark': 'user-check', 'person.crop.circle.badge.xmark': 'user-x',
    'person.xmark': 'user-x', 'person.2.slash': 'user-x', 'person.crop.circle.badge.questionmark': 'user-search', 'person.crop.circle.badge.magnifyingglass': 'user-search',
    'pawprint': 'paw-print', 'dog': 'dog', 'cat': 'cat', 'bird': 'bird', 'fish': 'fish', 'hare': 'rabbit', 'ladybug': 'bug',
    'bed.double': 'bed-double', 'checkmark': 'check', 'checkmark.circle': 'circle-check', 'checkmark.seal': 'badge-check', 'checkmark.square': 'square-check',
    'checkmark.shield': 'shield-check', 'checklist': 'list-checks', 'calendar': 'calendar', 'calendar.badge.plus': 'calendar-plus', 'calendar.badge.clock': 'calendar-clock',
    'calendar.badge.checkmark': 'calendar-check', 'calendar.badge.minus': 'calendar-minus', 'calendar.badge.exclamationmark': 'calendar-x',
    'exclamationmark.triangle': 'triangle-alert', 'exclamationmark.circle': 'circle-alert', 'exclamationmark.shield': 'shield-alert',
    'door.left.hand.open': 'door-open', 'door.left.hand.closed': 'door-closed', 'trash': 'trash-2', 'xmark': 'x', 'xmark.circle': 'circle-x',
    'lock': 'lock', 'lock.open': 'lock-open', 'lock.shield': 'lock-keyhole', 'house': 'house', 'building.2': 'building-2', 'building.columns': 'landmark',
    'storefront': 'store', 'dollarsign.circle': 'circle-dollar-sign', 'banknote': 'banknote', 'creditcard': 'credit-card', 'wallet.pass': 'wallet',
    'receipt': 'receipt', 'percent': 'percent', 'signature': 'signature', 'pencil.and.scribble': 'signature', 'arrow.uturn.backward': 'undo-2',
    'arrow.uturn.backward.circle': 'undo-2', 'arrowshape.turn.up.left': 'reply', 'message': 'message-circle', 'bubble.left': 'message-circle',
    'text.bubble': 'message-square-text', 'questionmark.bubble': 'message-circle-question', 'bubble.left.and.bubble.right': 'messages-square',
    'bubble.left.and.text.bubble.right': 'messages-square', 'bubble.left.and.exclamationmark.bubble.right': 'messages-square', 'character.bubble': 'languages',
    'link': 'link', 'link.circle': 'link', 'link.badge.plus': 'link-2', 'list.clipboard': 'clipboard-list', 'globe': 'globe', 'globe.americas': 'earth',
    'clock.arrow.circlepath': 'history', 'clock': 'clock', 'alarm': 'alarm-clock', 'hourglass': 'hourglass', 'stethoscope': 'stethoscope',
    'doc': 'file', 'doc.text': 'file-text', 'doc.plaintext': 'file-text', 'doc.richtext': 'file-text', 'doc.on.doc': 'copy', 'doc.badge.plus': 'file-plus',
    'doc.badge.ellipsis': 'file-clock', 'doc.text.magnifyingglass': 'file-search', 'arrow.down.doc': 'file-down', 'note.text': 'notebook-text',
    'shippingbox': 'package', 'shippingbox.and.arrow.backward': 'package-open', 'arrow.left.arrow.right': 'arrow-left-right', 'arrow.triangle.swap': 'arrow-left-right',
    'phone': 'phone', 'phone.arrow.up.right': 'phone-outgoing', 'phone.arrow.down.left': 'phone-incoming', 'iphone': 'smartphone',
    'laptopcomputer.and.iphone': 'monitor-smartphone', 'mappin': 'map-pin', 'mappin.and.ellipse': 'map-pin', 'mappin.circle': 'map-pin', 'mappin.slash': 'map-pin-off',
    'map': 'map', 'location.north.line': 'navigation', 'location.viewfinder': 'locate-fixed', 'point.topleft.down.to.point.bottomright.curvepath': 'route',
    'point.3.connected.trianglepath.dotted': 'waypoints', 'scissors': 'scissors', 'arrow.up.right.square': 'square-arrow-out-up-right',
    'arrow.right': 'arrow-right', 'arrow.left': 'arrow-left', 'arrow.up': 'arrow-up', 'arrow.down': 'arrow-down', 'arrow.up.right': 'arrow-up-right',
    'arrow.up.arrow.down': 'arrow-up-down', 'arrow.up.to.line': 'arrow-up-to-line', 'arrow.down.to.line': 'arrow-down-to-line', 'arrow.right.to.line': 'arrow-right-to-line',
    'arrow.triangle.merge': 'merge', 'arrow.clockwise': 'rotate-cw', 'arrow.counterclockwise': 'rotate-ccw', 'arrow.triangle.2.circlepath': 'refresh-cw',
    'arrow.up.right.circle': 'circle-arrow-out-up-right', 'arrow.up.circle': 'circle-arrow-up', 'arrow.down.circle': 'circle-arrow-down', 'arrow.down.right.circle': 'circle-arrow-down',
    'repeat': 'repeat', 'shuffle': 'shuffle', 'key': 'key-round', 'ellipsis': 'ellipsis', 'ellipsis.circle': 'circle-ellipsis', 'paperplane': 'send',
    'hand.raised': 'hand', 'hand.thumbsup': 'thumbs-up', 'hand.thumbsdown': 'thumbs-down', 'bell': 'bell', 'bell.badge': 'bell-dot', 'bell.slash': 'bell-off',
    'bell.and.waves.left.and.right': 'bell-ring', 'app.badge': 'bell-dot', 'tag': 'tag', 'pills': 'pill', 'syringe': 'syringe', 'cross.case': 'briefcase-medical',
    'bandage': 'bandage', 'thermometer.medium': 'thermometer', 'testtube.2': 'test-tubes', 'flask': 'flask-conical', 'waveform.path.ecg': 'activity',
    'heart': 'heart', 'heart.circle': 'heart', 'heart.text.square': 'heart-pulse', 'scalemass': 'weight', 'square.and.arrow.up': 'share', 'square.and.arrow.down': 'download',
    'square.and.arrow.down.on.square': 'download', 'photo.badge.arrow.down': 'image-down', 'play': 'play', 'play.circle': 'circle-play', 'pause.circle': 'circle-pause',
    'stop': 'square', 'forward.end': 'skip-forward', 'archivebox': 'archive', 'sparkles': 'sparkles', 'hands.and.sparkles': 'sparkles', 'envelope': 'mail',
    'envelope.badge': 'mail', 'envelope.open': 'mail-open', 'envelope.badge.shield.half.filled': 'mail-check', 'magnifyingglass': 'search',
    'rectangle.portrait.and.arrow.right': 'log-out', 'eye': 'eye', 'eye.slash': 'eye-off', 'cart': 'shopping-cart', 'bag': 'shopping-bag', 'bolt': 'zap',
    'sun.max': 'sun', 'moon': 'moon', 'moon.stars': 'moon-star', 'star': 'star', 'safari': 'compass', 'light.beacon.max': 'siren', 'circle': 'circle',
    'circle.dashed': 'circle-dashed', 'largecircle.fill.circle': 'circle-dot', 'square.stack.3d.up': 'layers', 'photo': 'image', 'photo.on.rectangle': 'images',
    'nosign': 'ban', 'gearshape': 'settings', 'figure.walk': 'footprints', 'barcode.viewfinder': 'scan-barcode', 'qrcode': 'qr-code', 'wrench.and.screwdriver': 'wrench',
    'hammer': 'hammer', 'tray': 'inbox', 'tablecells': 'table', 'slider.horizontal.3': 'sliders-horizontal', 'line.3.horizontal.decrease': 'list-filter',
    'line.3.horizontal.decrease.circle': 'list-filter', 'list.bullet.indent': 'list-indent-increase', 'questionmark.circle': 'circle-help', 'questionmark.diamond': 'circle-help',
    'info.circle': 'info', 'printer': 'printer', 'plus.circle': 'circle-plus', 'plus.square.on.square': 'copy-plus', 'minus.square': 'square-minus',
    'paperclip': 'paperclip', 'leaf': 'leaf', 'camera': 'camera', 'square.grid.2x2': 'layout-grid', 'square': 'square', 'graduationcap': 'graduation-cap',
    'fork.knife': 'utensils', 'chart.bar': 'chart-column', 'chart.line.uptrend.xyaxis': 'trending-up', 'backpack': 'backpack', 'at': 'at-sign',
    'wifi.exclamationmark': 'wifi-off', 'icloud.slash': 'cloud-off', 'snowflake': 'snowflake', 'shower': 'shower-head', 'bathtub': 'bath', 'shield': 'shield',
    'seal': 'badge', 'scroll': 'scroll-text', 'rosette': 'award', 'plusminus': 'diff', 'party.popper': 'party-popper', 'line.diagonal': 'slash',
    'gauge.with.dots.needle.33percent': 'gauge', 'flashlight.on': 'flashlight', 'flashlight.off': 'flashlight-off', 'dumbbell': 'dumbbell',
    'dot.radiowaves.left.and.right': 'radio', 'cup.and.saucer': 'coffee', 'crown': 'crown', 'chair': 'armchair', 'bookmark': 'bookmark', 'book': 'book-open',
    'list.bullet': 'list', 'list.bullet.rectangle': 'list', 'rectangle.split.3x1': 'columns-3', 'calendar.day.timeline.left': 'calendar-days',
    'person.fill.questionmark': 'user-search', 'tennisball': 'circle-dot', 'lizard': 'turtle', 'sidebar.left': 'panel-left', 'globe.badge.chevron.backward': 'languages',
}

def kebab(name):
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', name)
    s = re.sub(r'([A-Z])([A-Z][a-z])', r'\1-\2', s)
    return re.sub(r'([a-zA-Z])([0-9])', r'\1-\2', s).lower()

# Aliases (AlertTriangle → triangle-alert) from the package's export list.
aliases = {}
index = open(os.path.join(LUCIDE, 'lucide-react.js')).read()
for alias, file in re.findall(r"default as (\w+)[^']*'\./icons/([a-z0-9-]+)\.js'", index):
    aliases[alias] = file
for m in re.finditer(r"export \{([^}]*)\} from '\./icons/([a-z0-9-]+)\.js'", index):
    for part in m.group(1).split(','):
        part = part.strip()
        if ' as ' in part:
            aliases[part.split(' as ')[1].strip()] = m.group(2)

used = set()
for root, _, files in os.walk(os.path.join(WEB, 'src')):
    for f in files:
        if f.endswith(('.tsx', '.ts')):
            text = open(os.path.join(root, f), errors='ignore').read()
            for block in re.findall(r"import \{([^}]+)\} from 'lucide-react'", text):
                for part in block.split(','):
                    part = part.strip().replace('type ', '')
                    if not part:
                        continue
                    name = part.split(' as ')[0].strip()
                    if name in ('LucideIcon', 'LucideProps', 'IconNode'):
                        continue
                    used.add(name)

def canonical(name):
    """Follow an alias file (`export { default } from './x.js'`) to the icon it points at."""
    path = os.path.join(LUCIDE, 'icons', name + '.js')
    if not os.path.exists(path):
        return None
    m = re.search(r"export \{ default \} from '\./([a-z0-9-]+)\.js'", open(path).read())
    return canonical(m.group(1)) if m else name

def file_for(component):
    for candidate in (aliases.get(component), aliases.get(component + 'Icon'), kebab(component.removesuffix('Icon')), kebab(component)):
        if candidate and canonical(candidate):
            return canonical(candidate)
    return None

# Icons the app draws that the web takes from elsewhere (sonner's, the shell's).
EXTRA = ['octagon-x', 'panel-left', 'circle-check', 'rows-3', 'calendar-clock', 'calendar-check-2', 'layout-grid', 'hospital',
         'boxes', 'coins', 'bell-ring', 'mail-plus', 'shield-check', 'door-open', 'map-pin', 'receipt', 'user-round', 'rat', 'turtle',
         'rabbit', 'dog', 'cat', 'bird', 'fish', 'paw-print', 'notebook-pen', 'zap', 'calendar-plus', 'badge-check', 'link-2', 'banknote',
         'ellipsis', 'circle-dot', 'x', 'languages', 'chevrons-up-down', 'layers', 'external-link', 'log-out', 'arrow-left-right',
         'users-round', 'clock-3', 'message-circle-question-mark', 'eye-off', 'eye', 'list', 'calendar-days', 'sun', 'moon', 'triangle-alert']
wanted = {f for f in (file_for(c) for c in used) if f} | {canonical(n) for n in EXTRA if canonical(n)}
missing_map = {}
for sf, lucide in list(SF.items()):
    if canonical(lucide):
        SF[sf] = canonical(lucide)
        wanted.add(SF[sf])
    else:
        missing_map[sf] = lucide

def svg(name):
    text = open(os.path.join(LUCIDE, 'icons', name + '.js')).read()
    nodes = re.search(r'const __iconNode = (\[.*?\]);', text, re.S).group(1)
    parts = []
    for tag, attrs in re.findall(r'\[\s*"(\w+)",\s*\{(.*?)\}\s*\]', nodes, re.S):
        pairs = re.findall(r'(\w+): "([^"]*)"', attrs)
        attr = ' '.join(f'{k}="{v}"' for k, v in pairs if k != 'key')
        parts.append(f'<{tag} {attr}/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
            'stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + ''.join(parts) + '</svg>\n')

shutil.rmtree(ASSETS, ignore_errors=True)
os.makedirs(ASSETS)
json.dump({'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(ASSETS, 'Contents.json'), 'w'), indent=2)
for name in sorted(wanted):
    folder = os.path.join(ASSETS, f'lucide-{name}.imageset')
    os.makedirs(folder)
    open(os.path.join(folder, f'{name}.svg'), 'w').write(svg(name))
    json.dump({'images': [{'filename': f'{name}.svg', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1},
               'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}},
              open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)

mapped = {sf: l for sf, l in SF.items() if sf not in missing_map}
# Older names of the same icons (message-circle-question → message-circle-question-mark), so a
# screen can use the name the web's import has.
alias_map = {}
for f in os.listdir(os.path.join(LUCIDE, 'icons')):
    if f.endswith('.js'):
        name = f[:-3]
        target = canonical(name)
        if target and target != name and target in wanted:
            alias_map[name] = target
lines = ['//', '//  GlyphNames.swift', '//  PawMiawNegocios', '//', '//  Generated by scripts/lucide-icons.py — do not edit by hand. The SF Symbol',
         '//  names the screens use, mapped to the web\'s Lucide icons (Assets.xcassets/Lucide).', '//', '',
         'enum GlyphNames {', '    /// Every Lucide icon in the asset catalog.',
         '    static let lucide: Set<String> = [' + ', '.join(f'"{n}"' for n in sorted(wanted)) + ']', '',
         '    /// SF Symbol (without ".fill") → Lucide.', '    static let sf: [String: String] = [']
lines += [f'        "{k}": "{v}",' for k, v in sorted(mapped.items())]
lines += ['    ]', '', '    /// Older Lucide names → the icon in the catalog.', '    static let aliases: [String: String] = [']
lines += [f'        "{k}": "{v}",' for k, v in sorted(alias_map.items())]
lines += ['    ]', '}', '']
open(SWIFT, 'w').write('\n'.join(lines))
print(f'{len(wanted)} icons, {len(mapped)} SF names mapped; map targets not in lucide: {missing_map}')
