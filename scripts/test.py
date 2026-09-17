import os
from pathlib import Path
from lua_host import Lua, literal

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get('HD2_GAME_ROOT', r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2'))

if __name__ == '__main__':
    for test in sorted((ROOT / 'tests').glob('test_*.lua')):
        lua = Lua(GAME / 'bin/lua51.dll')
        try:
            result = lua.run('ROOT=' + literal(ROOT.as_posix().encode()) + ';return assert(loadfile(' + literal(test.as_posix().encode()) + '))()')
            print(result.decode(), flush=True)
        finally:
            lua.close()
