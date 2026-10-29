#!/usr/bin/env python3
"""Static checks for the addon's Lua (runs anywhere, no Lua needed):
  1. Lua 5.2+ syntax that WoW's Lua 5.1 does not have: goto, ::labels::, //, bitwise operators &, |, ~ (binary), <<, >>.
  2. Compliance: functions the addon must never call (code execution from strings, casting, targeting, following,
     moving, quest/taxi automation, chat, secure action buttons).
Usage: python3 tools/lint51.py [files...]   (default: every .lua under WoWBoxer/)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FORBIDDEN = [
    'loadstring', 'RunScript', 'setfenv', 'getfenv', 'load',
    'CastSpell', 'CastSpellByName', 'CastSpellByID', 'CastShapeshiftForm', 'UseAction', 'UseItemByName', 'UseContainerItem',
    'RunMacro', 'RunMacroText', 'RunBinding',
    'FollowUnit', 'AssistUnit', 'TargetUnit', 'FocusUnit', 'ClearFocus', 'TargetNearestEnemy', 'AttackTarget', 'StartAttack',
    'MoveForwardStart', 'JumpOrAscendStart', 'ToggleAutoRun', 'InteractUnit',
    'AcceptQuest', 'CompleteQuest', 'GetQuestReward', 'AcceptGroup', 'TakeTaxiNode', 'RepairAllItems', 'SellCursorItem',
    'SendChatMessage', 'SetRaidTarget', 'LearnTalent', 'PetAttack', 'PetFollow',
    'SecureActionButtonTemplate', 'SecureHandlerBaseTemplate', 'SecureHandlerWrapScript', 'SetOverrideBinding', 'SetOverrideBindingClick',
]
# Automation through WoW's normal addon API (CLAUDE.md hard rule 1, the owner 29 Oct 2026): allowed ONLY in WoWBoxer/Auto.lua,
# where every call sits behind a Setup → Automation option and a squad-member check. Casting, targeting, moving,
# following and NPC interaction stay forbidden everywhere.
AUTOMATION = {'AcceptQuest', 'CompleteQuest', 'GetQuestReward', 'AcceptGroup', 'TakeTaxiNode', 'RepairAllItems', 'UseContainerItem'}
AUTOMATION_FILES = {'Auto.lua'}
# Writes to keybinds, action slots and the cursor: only in Binds.lua / Bars.lua (one place, a source= log line each,
# docs/feedback-2026-10-30-night.md §3.2) – also when called as G.X or _G.X.
WRITE_API = {'SetBinding', 'SetBindingMacro', 'SetBindingClick', 'SetBindingSpell', 'SetBindingItem', 'SaveBindings',
             'PlaceAction', 'PickupAction', 'ClearCursor', 'PickupMacro', 'PickupSpell', 'PickupItem'}
WRITE_FILES = {'Binds.lua', 'Bars.lua'}
FORBIDDEN_RE = re.compile(r'(?<![\w.:])(' + '|'.join(map(re.escape, FORBIDDEN)) + r')(?!\w)')


def tokens(src):
    """Yield (kind, text, line) with comments and strings removed (strings are yielded as 'str')."""
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1; i += 1; continue
        if c in ' \t\r':
            i += 1; continue
        if src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                end = src.find(']' + m.group(1) + ']', i)
                end = n if end < 0 else end + len(m.group(1)) + 2
                line += src.count('\n', i, end); i = end
            else:
                end = src.find('\n', i); i = n if end < 0 else end
            continue
        m = re.match(r'\[(=*)\[', src[i:])
        if m:
            end = src.find(']' + m.group(1) + ']', i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            yield ('str', src[i:end], line); line += src.count('\n', i, end); i = end; continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    j += 1
                if j < n and src[j] == '\n':
                    line += 1
                j += 1
            yield ('str', src[i:j + 1], line); i = j + 1; continue
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src[i:])
        if m:
            yield ('name', m.group(0), line); i += len(m.group(0)); continue
        m = re.match(r'0[xX][0-9a-fA-F]+|\d+\.?\d*([eE][-+]?\d+)?|\.\d+', src[i:])
        if m:
            yield ('num', m.group(0), line); i += len(m.group(0)); continue
        for op in ('...', '..', '==', '~=', '<=', '>=', '::', '//', '<<', '>>'):
            if src.startswith(op, i):
                yield ('op', op, line); i += len(op); break
        else:
            yield ('op', c, line); i += 1


def check(path):
    with open(path, encoding='utf-8') as f:
        src = f.read()
    errs = []
    prev = None
    for kind, text, line in tokens(src):
        if kind == 'name' and text == 'goto':
            errs.append((line, 'goto is Lua 5.2+'))
        if kind == 'op' and text in ('::', '//', '<<', '>>', '&', '|'):
            errs.append((line, 'operator %s is Lua 5.2+/5.3+' % text))
        if kind == 'op' and text == '~':
            errs.append((line, 'operator ~ is Lua 5.3+'))
        if kind == 'str' and text[:1] in '"\'':
            # Lua 5.1 silently drops an unknown escape: "Interface\Icons\X" becomes "InterfaceIconsX" (no error)
            k = 1
            while k < len(text) - 1:
                if text[k] == '\\':
                    nxt = text[k + 1]
                    if nxt not in 'abfnrtv\\"\'0123456789\n':
                        errs.append((line, 'invalid escape \\%s in string (use \\\\ for a path)' % nxt))
                        break
                    k += 2
                else:
                    k += 1
        automation_ok = text in AUTOMATION and os.path.basename(path) in AUTOMATION_FILES
        write_ok = os.path.basename(path) in WRITE_FILES or (prev and prev[0] == 'op' and prev[1] == ':')
        if kind == 'name' and text in WRITE_API and not write_ok:
            errs.append((line, '%s outside Binds.lua / Bars.lua (use the write layer there)' % text))
        if kind == 'name' and FORBIDDEN_RE.fullmatch(text) and not (prev and prev[0] == 'op' and prev[1] in ('.', ':')) and not automation_ok:
            errs.append((line, 'forbidden call/name: %s' % text))
        prev = (kind, text)
    return errs


def main(argv):
    files = argv[1:]
    if not files:
        for d, _, fs in os.walk(os.path.join(ROOT, 'WoWBoxer')):
            files += [os.path.join(d, f) for f in fs if f.endswith('.lua')]
    bad = 0
    for p in sorted(files):
        for line, msg in check(p):
            print('%s:%d: %s' % (os.path.relpath(p, ROOT), line, msg))
            bad += 1
    print('lint51: %d file(s), %d problem(s)' % (len(files), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
