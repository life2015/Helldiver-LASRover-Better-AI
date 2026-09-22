"""Validate the exact Lua snapshot/policy externally using VM_READ only.

No game writes, injection, game files changed, or mod installation required.
The game Lua DLL is loaded into this Python process for matching FFI semantics.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
import sys
import time
from pathlib import Path

from lua_host import Lua, literal
from test import ROOT, GAME

sys.path.insert(0, str(ROOT.parent / 'research'))
from observe_rover import Reader, GAME_SHA, EXE_SHA


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--seconds', type=float, default=40)
    args = parser.parse_args()
    if not 0 < args.seconds <= 60:
        parser.error('Duration must be within 0..60 seconds')
    reader = Reader(args.pid)
    lua = None
    try:
        modules = reader.modules()
        hashes={name:hashlib.sha256(modules[name][1].read_bytes()).hexdigest().upper()
                for name in ['game.dll','helldivers2.exe']}
        base = modules['game.dll'][0]
        lua = Lua(GAME / 'bin/lua51.dll')
        layout_file=literal((ROOT/'src/layout.lua').as_posix().encode())
        selection=lua.run('local p=assert(loadfile('+layout_file+'))().profiles;for i,v in ipairs(p)do '
            +'if v.game_sha=='+literal(hashes['game.dll'].encode())+' and v.exe_sha=='
            +literal(hashes['helldivers2.exe'].encode())+' then return tostring(i) end end;return "0"').decode()
        layout_index=int(selection)
        if layout_index==0:
            if hashes['game.dll']!=GAME_SHA.upper() or hashes['helldivers2.exe']!=EXE_SHA.upper():
                raise ValueError('Unsupported module pair; no verified layout')
            signatures=[(0x6b7f20,'405741574883ec283b1532ed0c02450fb6f94c8b15074b0b'),
                        (0x2609d0,'40554154488dac24f8fdffff4881ec08030000440f298c24'),
                        (0x260f5c,'488b1505b15002498b4c24084c8b42184c3981900000000f')]
        else:
            encoded=lua.run('local rows={};for _,s in ipairs(assert(loadfile('+layout_file+'))().profiles['
                +str(layout_index)+'].signatures)do rows[#rows+1]=tostring(s[1])..":"..s[2] end;return table.concat(rows,";")').decode()
            signatures=[(int(a),b) for a,b in (row.split(':') for row in encoded.split(';'))]
        for rva,signature in signatures:
            expected=bytes.fromhex(signature)
            if reader.read(base+rva,len(expected))!=expected:raise ValueError('Runtime signature mismatch')
        lib = lua.lib
        lib.lua_tonumber.argtypes = [C.c_void_p, C.c_int]
        lib.lua_tonumber.restype = C.c_double
        lib.lua_pushlstring.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t]
        lib.lua_pushcclosure.argtypes = [C.c_void_p, C.c_void_p, C.c_int]
        lib.lua_setfield.argtypes = [C.c_void_p, C.c_int, C.c_char_p]
        trace, read_errors = [], []

        @C.CFUNCTYPE(C.c_int, C.c_void_p)
        def read_callback(state):
            try:
                address, size = int(lib.lua_tonumber(state, 1)), int(lib.lua_tonumber(state, 2))
                data = reader.read(address, size)
                trace.append({'address': address, 'hex': data.hex()})
                lib.lua_pushlstring(state, data, len(data))
                return 1
            except Exception as exc:
                read_errors.append(str(exc))
                return 0

        lib.lua_pushcclosure(lua.state, read_callback, 0)
        lib.lua_setfield(lua.state, -10002, b'host_read')
        lua.run('ROOT=' + literal(ROOT.as_posix().encode()) + ';LAYOUT_INDEX='+str(layout_index)+';GAME=' + str(base) + ';EXE=' + str(modules['helldivers2.exe'][0]))
        lua.run('''
            local ffi=require('ffi')
            local function load(name)return assert(loadfile(ROOT..'/src/'..name..'.lua'))()end
            local api={read=host_read,time=function()return HOST_NOW end,
                pointer=function(b)
                    local p=ffi.new('uint64_t[1]');ffi.copy(p,b,8);local n=tonumber(p[0])
                    return n>=0x10000 and n<0x800000000000 and n or nil
                end,
                write=function()error('read-only observer')end}
            api.layout=load('layout').profiles[LAYOUT_INDEX]
            local markers=load('markers');api.markers=function(game,owner,candidates)return markers.read(api,game,owner,candidates)end
            local snapshot=load('snapshot')
            local position=load('position')
            api.position=function(unit)return position.read(api,EXE,unit)end
            local raw_read=snapshot.read
            snapshot.read=function(...)
                local s,why=raw_read(...);LAST_SNAPSHOT=s;return s,why
            end
            CONTROL=load('controller')(api,snapshot,load('policy'),load('lease'),GAME,false)
            function sample()
                local ok,why=pcall(CONTROL.poll)
                if not ok then return 'error\t'..tostring(why)end
                local s=LAST_SNAPSHOT;local rows={};local distances={}
                if s then for _,c in ipairs(s.candidates)do
                    rows[#rows+1]=string.format('%d:%d',c.id,c.eligible and 1 or 0)
                    distances[#distances+1]=string.format('%d:%s',c.id,c.distance2 and string.format('%.3f',math.sqrt(c.distance2)) or 'unknown')
                end end
                return table.concat({CONTROL.status or '',CONTROL.id or 0,CONTROL.target or 0,
                    CONTROL.node or 0,CONTROL.eligible or 0,CONTROL.would_rotate or 0,table.concat(rows,','),
                    s and s.distance_available and '1' or '0',table.concat(distances,','),CONTROL.planned_target or 0,
                    CONTROL.ranking or '',CONTROL.history_count or 0,CONTROL.decision or '',
                    CONTROL.no_attack_elapsed or 0,CONTROL.marked_target or 0,CONTROL.marker_status or '',CONTROL.selection_basis or ''},'\t')
            end
        ''')
        folder = ROOT.parent / 'research/artifacts'
        folder.mkdir(exist_ok=True)
        stem = folder / ('rover-policy-' + time.strftime('%Y%m%d-%H%M%S'))
        start = time.perf_counter()
        runtime_log = Path(os.environ.get('LOCALAPPDATA', '.')) / 'RoverFireSpread.log'
        saved = set()
        print(json.dumps({'status': 'sampling_read_only', 'output': str(stem.with_suffix('.jsonl'))}), flush=True)
        with stem.with_suffix('.jsonl').open('x', encoding='utf-8') as output:
            while time.perf_counter() - start < args.seconds:
                trace.clear(); read_errors.clear()
                now = time.perf_counter() - start
                fields = lua.run(f'HOST_NOW={now!r};return sample()').decode().split('\t')
                row = {'time': now, 'status': fields[0], 'fields': fields[1:], 'read_errors': read_errors.copy()}
                try:
                    row['mod_log'] = dict(line.split('=', 1) for line in runtime_log.read_text(encoding='utf-8').splitlines() if '=' in line)
                    row['mod_log_mtime'] = runtime_log.stat().st_mtime
                except (OSError, UnicodeError):
                    row['mod_log'] = None
                output.write(json.dumps(row) + '\n'); output.flush()
                # Keep one sparse read trace per outcome for offline diagnosis.
                category = fields[0] + (fields[1] if fields[0] == 'error' and len(fields)>1 else '')
                if category not in saved and len(saved)<10:
                    saved.add(category)
                    stem.with_suffix(f'.trace{len(saved)}.json').write_text(json.dumps({'row':row,'base':base,'reads':trace}), encoding='utf-8')
                    print(json.dumps(row), flush=True)
                if any('Access is denied' in e or 'WinError 5]' in e for e in read_errors):
                    raise RuntimeError('Read access denied; observation stopped')
                time.sleep(.1)
        print(json.dumps({'status':'complete','output':str(stem.with_suffix('.jsonl'))}), flush=True)
    finally:
        if lua is not None:
            lua.close()
        reader.close()


if __name__ == '__main__':
    main()
