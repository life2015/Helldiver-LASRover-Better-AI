"""Compile a matching LuaJIT entry chunk. Default mode never writes game memory."""
import argparse
import hashlib
import json
from pathlib import Path
from lua_host import Lua
from test import ROOT, GAME


def compile_entry(enabled=False, show_hud=True):
    names = ['layout', 'windows_api', 'position', 'markers', 'snapshot', 'policy', 'lease', 'controller', 'hud', 'install']
    if not show_hud:
        names.remove('hud')
    parts = ['-- Private prototype; gameplay effect still requires in-game testing.']
    if not show_hud:
        parts.append('local hud=nil -- No HUD implementation included in this build.')
    for name in names:
        parts.append('local ' + name + '=(function()\n' + (ROOT / 'src' / (name + '.lua')).read_text(encoding='utf-8') + '\nend)()')
    parts.append('''local function create_api()
        local api=windows_api();local exe=api.module(nil)
        api.position=function(unit)return position.read(api,exe,unit)end
        api.markers=function(game,owner,candidates)return markers.read(api,game,owner,candidates)end
        return api
    end
    install(create_api,snapshot,policy,lease,controller,{
        layouts=layout.profiles,
        enabled=false,
        show_hud=true,
        game_sha='CC75948D90FDFDE259DCB519E9933DB7FFA3CCB281CE4FB89E6B1B011557470C',
        exe_sha='A09FF52663E73B94FB0CAC0DCB5BA84FFD10ECF44F74A8921AC66AF923988CC3',
        signatures={{0x6b7f20,'405741574883ec283b1532ed0c02450fb6f94c8b15074b0b'},
            {0x2609d0,'40554154488dac24f8fdffff4881ec08030000440f298c24'},
            {0x260f5c,'488b1505b15002498b4c24084c8b42184c3981900000000f'}}
    },hud)''')
    source = '\n'.join(parts).replace('enabled=false,', 'enabled=' + ('true' if enabled else 'false') + ',')
    source = source.replace('show_hud=true,', 'show_hud=' + ('true' if show_hud else 'false') + ',')
    lua = Lua(GAME / 'bin/lua51.dll')
    try:
        code = lua.compile(source)
    finally:
        lua.close()
    folder = ROOT / 'build'
    folder.mkdir(exist_ok=True)
    mode='experimental' if enabled else 'diagnostic'
    suffix='' if show_hud else '-no-hud'
    (folder / ('rover_fire_spread.'+mode+suffix+'.lua')).write_text(source, encoding='utf-8')
    (folder / ('rover_fire_spread.'+mode+suffix+'.luac')).write_bytes(code)
    report = {'mode': mode, 'installable': False, 'gameplay_validated': False,
              'variant': 'hud' if show_hud else 'no-hud', 'hud_enabled': show_hud,
              'bytecode_sha256': hashlib.sha256(code).hexdigest(),
              'supported_layout_ids': ['24826606','25327279'],
              'lua_dll_sha256': hashlib.sha256((GAME / 'bin/lua51.dll').read_bytes()).hexdigest(),
              'sources': {name: hashlib.sha256((ROOT / 'src' / (name + '.lua')).read_bytes()).hexdigest() for name in names}}
    (folder / ('build-report'+suffix+'.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
    return code, report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experimental',action='store_true')
    parser.add_argument('--no-hud',action='store_true',help='Omit HUD implementation and all GUI creation/drawing')
    args=parser.parse_args()
    code,report=compile_entry(args.experimental,show_hud=not args.no_hud)
    print(json.dumps({'compiled_bytes':len(code),'mode':report['mode']}))


if __name__ == '__main__':
    main()
