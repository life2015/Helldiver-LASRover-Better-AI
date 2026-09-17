"""Compile a matching LuaJIT entry chunk. Default mode never writes game memory."""
import argparse
import hashlib
import json
from pathlib import Path
from lua_host import Lua
from test import ROOT, GAME


def compile_entry(enabled=False):
    names = ['windows_api', 'snapshot', 'policy', 'lease', 'controller', 'install']
    parts = ['-- Private prototype; gameplay effect still requires in-game testing.']
    for name in names:
        parts.append('local ' + name + '=(function()\n' + (ROOT / 'src' / (name + '.lua')).read_text(encoding='utf-8') + '\nend)()')
    parts.append('''install(windows_api,snapshot,policy,lease,controller,{
        enabled=false,
        game_sha='CC75948D90FDFDE259DCB519E9933DB7FFA3CCB281CE4FB89E6B1B011557470C',
        exe_sha='A09FF52663E73B94FB0CAC0DCB5BA84FFD10ECF44F74A8921AC66AF923988CC3',
        signatures={{0x6b7f20,'405741574883ec283b1532ed0c02450fb6f94c8b15074b0b'}}
    })''')
    source = '\n'.join(parts).replace('enabled=false,', 'enabled=' + ('true' if enabled else 'false') + ',')
    lua = Lua(GAME / 'bin/lua51.dll')
    try:
        code = lua.compile(source)
    finally:
        lua.close()
    folder = ROOT / 'build'
    folder.mkdir(exist_ok=True)
    mode='experimental' if enabled else 'diagnostic'
    (folder / ('rover_fire_spread.'+mode+'.lua')).write_text(source, encoding='utf-8')
    (folder / ('rover_fire_spread.'+mode+'.luac')).write_bytes(code)
    report = {'mode': mode, 'installable': False, 'gameplay_validated': False,
              'bytecode_sha256': hashlib.sha256(code).hexdigest(),
              'lua_dll_sha256': hashlib.sha256((GAME / 'bin/lua51.dll').read_bytes()).hexdigest(),
              'sources': {name: hashlib.sha256((ROOT / 'src' / (name + '.lua')).read_bytes()).hexdigest() for name in names}}
    (folder / 'build-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return code, report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experimental',action='store_true')
    args=parser.parse_args()
    code,report=compile_entry(args.experimental)
    print(json.dumps({'compiled_bytes':len(code),'mode':report['mode']}))


if __name__ == '__main__':
    main()
