"""Wrap each current HUD/No HUD core with the fixed published v14 startup."""
import json
import struct
import zipfile
from pathlib import Path

from package import extract, sha, resource_hash, make_archive, ARCHIVE, CALLBACK, MODULE, VERSION, PACKAGE_NAME, load_base, package_name
from lua_host import Lua, literal
from test import ROOT, GAME

LOADER_SHA = '7FA8AF328AC2C98F68DD5946D94444315DD61B2B3504B0788301700CC9C023B2'
CALLBACK_SHA = 'B2E82518373E7EB85315C54B5829F8FD2BB1277D1690E40476354111B1608210'


def build_variant(show_hud):
    base, base_report = load_base(show_hud)
    variant = 'hud' if show_hud else 'no-hud'
    suffix = '' if show_hud else '-No-HUD'
    label = 'HUD' if show_hud else 'No HUD'
    loader = ROOT / 'build/Bingus-Shared-Loader-v14.zip'
    assert sha(loader.read_bytes()) == LOADER_SHA, 'Unexpected published v14 ZIP'
    folder = ROOT / 'build/v14-compat' / variant
    folder.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(base) as z:
        resources = extract(z.read('data/' + ARCHIVE))
        rover = resources[resource_hash(MODULE)]
        report = json.loads(z.read('provenance.json'))
        manifest = json.loads(z.read('manifest.json'))
    with zipfile.ZipFile(loader) as z:
        original = extract(z.read('data/' + ARCHIVE))[resource_hash(CALLBACK)]
    assert sha(original) == CALLBACK_SHA
    startup_path = ROOT / 'src/startup.lua'
    assert sha(startup_path.read_bytes()).lower() == report['startup_sha256'].lower(), 'Base startup source changed'
    startup = startup_path.read_text(encoding='utf-8').replace('experimental-'+VERSION, 'experimental-'+VERSION+'-v14'+suffix)
    startup = startup.replace("report('bridge_entered')", "report('bridge_entered');report('shared_loader_release=v14')")
    source = 'local start=(function()\n' + startup + '\nend)()\n'
    source += 'start(function() assert(loadstring(' + literal(original[8:]) + ", '@published_bingus_v14'))() end,\n"
    source += 'function() assert(loadstring(' + literal(rover[8:]) + ", '@rover_fire_spread_"+VERSION.replace('.','_')+"'))() end)\n"
    original_path, bridge_path = folder / 'published-v14.luac', folder / 'startup.luac'
    original_path.write_bytes(original[8:])
    lua = Lua(GAME / 'bin/lua51.dll')
    try:
        bridge = lua.compile(source)
        bridge_path.write_bytes(bridge)
        prefix = 'ORIGINAL=' + literal(original_path.as_posix().encode()) + ';BRIDGE=' + literal(bridge_path.as_posix().encode()) + ';'
        prefix += 'EXPECT_HUD='+('true' if show_hud else 'false')+';EXPECT_BUILD='+literal(('experimental-'+VERSION+'-v14'+suffix).encode())+';'
        tests = lua.run(prefix + 'return assert(loadfile(' + literal((ROOT / 'tests/check_v14_bridge.lua').as_posix().encode()) + '))()').decode()
    finally:
        lua.close()
    new_resources = {resource_hash(MODULE): rover,
                     resource_hash(CALLBACK): struct.pack('<II', len(bridge), 2) + bridge}
    archive = make_archive(new_resources)
    assert extract(archive) == new_resources
    report.update({
        'variant': variant, 'loader_channel':'v14', 'base_zip_sha256': base_report['zip_sha256'],
        'core_sources':base_report['sources'],
        'rover_resource_sha256': sha(rover), 'rover_resource_unchanged': True,
        'loader_release': 'https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v14',
        'loader_zip_sha256': LOADER_SHA, 'loader_callback_resource_sha256': CALLBACK_SHA,
        'startup_sha256': sha(startup.encode()), 'startup_tests': tests,
        'archive_sha256': sha(archive), 'gameplay_validated': False,
        'compatibility_runtime_validated': False,
        'priority_requirement': 'This package must win Wwise callback over standalone Bingus Shared Loader; resource overlap remains expected.'})
    name = f'{PACKAGE_NAME} {VERSION} v14 内置加载器 ({label})'
    description = (f'Includes the complete published Bingus Shared Loader v14, then starts Rover {VERSION} ({label}). '
                   'THIS PACKAGE MUST WIN the Wwise startup conflict over the standalone loader. '
                   'Arsenal default priority: put this last; first-mod priority: put this first. '
                   'Disable old Rover versions. Resource overlap warning is expected. Offline tested; in-game compatibility pending.')
    manifest.update(Name=name, Description=description)
    manifest['Options'] = [{'Name': name, 'Description': description, 'Include': ['data']}]
    guide = (f'Package variant: v14 / {label}\nChoose exactly one Rover ZIP. This bundled v14 bridge must win the Wwise conflict.\nNo HUD omits all Rover GUI code.\n\n'+(ROOT / 'docs/packaging-channels.md').read_text(encoding='utf-8')).encode('utf-8')
    files = {'data/' + ARCHIVE: archive, 'data/' + ARCHIVE + '.stream': b'',
             'data/' + ARCHIVE + '.gpu_resources': b'',
             'manifest.json': json.dumps(manifest, indent=2).encode(),
             'provenance.json': json.dumps(report, indent=2).encode(),
             'INSTALL.txt': guide}
    out = ROOT / 'releases' / package_name('v14',show_hud)
    with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None and set(z.namelist()) == set(files)
        result = extract(z.read('data/' + ARCHIVE))
        assert result == new_resources and result[resource_hash(MODULE)] == rover
    report.update(zip_name=out.name, zip_sha256=sha(out.read_bytes()))
    (folder / 'package-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(tests)
    print('PASS unchanged Rover resource, archive round-trip and ZIP integrity')
    print(out)
    print('SHA256=' + report['zip_sha256'])
    return report


def main():
    for show_hud in (True,False):
        build_variant(show_hud)


if __name__ == '__main__':
    main()
