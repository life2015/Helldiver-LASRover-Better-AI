"""Package a discoverable Rover addon with no Wwise/boot or bundled loader.

Uses the current verified HUD/No HUD base packages and fixed official v15 ZIP
for offline integration checks. Never deploys or launches the game.
"""
import json
import struct
import tempfile
import zipfile
from pathlib import Path

from package import extract, sha, resource_hash, make_archive, TYPE, ARCHIVE, CALLBACK, MODULE, VERSION, PACKAGE_NAME, load_base, package_name
from lua_host import Lua, literal
from test import ROOT, GAME

LOADER_SHA='FA766634DFF3F7D1FD9C5C0EBA72B1FBABAD8721710491CAAA4E12A598028CDA'
IMPL='mods/retrox/rover_fire_spread_impl'


def bodies(archive):
    magic,types,count=struct.unpack_from('<III',archive)
    assert magic==0xf0000011 and types==1 and 0<count<100
    table_end=72+32*types+80*count
    assert table_end<=len(archive)
    result={}
    for i in range(count):
        row=struct.unpack_from('<7Q6I',archive,72+32*types+80*i)
        name,kind,offset=row[:3];size=row[7]
        assert kind==TYPE and table_end<=offset and size>=8 and offset+size<=len(archive)
        length,version=struct.unpack_from('<II',archive,offset)
        assert version==2 and length==size-8 and name not in result
        result[name]=archive[offset+8:offset+size]
    return result


def build_variant(show_hud):
    base,verified_report=load_base(show_hud)
    variant='hud' if show_hud else 'no-hud'
    label='HUD' if show_hud else 'No HUD'
    loader=ROOT/'build/Bingus-Shared-Loader-v15.zip'
    assert sha(loader.read_bytes())==LOADER_SHA
    with zipfile.ZipFile(base) as z:
        core=extract(z.read('data/'+ARCHIVE))[resource_hash(MODULE)]
        manifest=json.loads(z.read('manifest.json'))
        base_report=json.loads(z.read('provenance.json'))
    with zipfile.ZipFile(loader) as z:
        loader_archive=z.read('data/'+ARCHIVE)
    loader_resources=bodies(loader_archive)
    entry=(ROOT/'src/addon_entry.lua').read_bytes()
    assert entry.startswith(('-- HD2-Addon: '+MODULE+'\n').encode()) and len(entry.splitlines()[0])+1<=256
    resources={resource_hash(MODULE):struct.pack('<II',len(entry),2)+entry,resource_hash(IMPL):core}
    assert not set(resources).intersection(loader_resources), 'Addon overlaps loader resources'
    assert resource_hash(CALLBACK) not in resources and resource_hash('boot') not in resources
    archive=make_archive(resources)
    readback=bodies(archive)
    assert readback=={resource_hash(MODULE):entry,resource_hash(IMPL):core[8:]}
    folder=ROOT/'build/v15-addon'/variant;folder.mkdir(parents=True,exist_ok=True)
    (folder/'entry.lua').write_bytes(entry);(folder/'implementation.luac').write_bytes(core[8:])
    (folder/'published-loader.luac').write_bytes(loader_resources[resource_hash(CALLBACK)])
    # Use Windows enumeration on isolated synthetic deployments, never game data.
    results=[]
    with tempfile.TemporaryDirectory(prefix='integration-',dir=folder) as temp:
        fixture=Path(temp).resolve();assert fixture.parent==folder.resolve()
        (fixture/'data').mkdir()
        for mode in ('loader_high','addon_high','missing_impl','no_addon'):
            rover_index,loader_index=(2,10) if mode!='addon_high' else (10,2)
            for index in (2,10):
                path=fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(index))
                if path.exists():path.unlink()
            (fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(loader_index))).write_bytes(loader_archive)
            if mode!='no_addon':
                (fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(rover_index))).write_bytes(archive)
            lua=Lua(GAME/'bin/lua51.dll')
            try:
                values={'FIXTURE':fixture.as_posix(),'BUILD':folder.as_posix(),'MODE':mode}
                prefix=';'.join(k+'='+literal(v.encode()) for k,v in values.items())+';'
                prefix+='EXPECT_HUD='+('true' if show_hud else 'false')+';'
                result=lua.run(prefix+'return assert(loadfile('+literal((ROOT/'tests/check_v15_addon.lua').as_posix().encode())+'))()').decode()
                results.append(result)
            finally:lua.close()
    name=f'{PACKAGE_NAME} {VERSION} v15 需要额外安装加载器 ({label})'
    desc=f'Requires separately installed Bingus Shared Loader v15 or newer. Discoverable addon only; no Wwise or boot replacement. Disable all old Rover packages before installing. Core identical to {VERSION} {label} build; live compatibility pending.'
    manifest.update(Name=name,Description=desc,Options=[{'Name':name,'Description':desc,'Include':['Addon']}])
    report={'variant':variant,'loader_channel':'v15','base_zip_sha256':verified_report['zip_sha256'],'core_build':'experimental-'+VERSION,
        'module':MODULE,'implementation':IMPL,'entry_sha256':sha(entry),'core_resource_sha256':sha(core),
        'core_resource_unchanged':True,'core_sources':base_report['sources'],
        'supported_layout_ids':base_report['supported_layout_ids'],
        'hud':base_report['hud'],'hud_enabled':show_hud,'target_policy':base_report['target_policy'],
        'requires':'Bingus Shared Loader v15 or newer / API 1',
        'tested_loader_zip_sha256':LOADER_SHA,'startup_tests':results,
        'bundled_loader':False,'wwise_replaced':False,'boot_replaced':False,
        'shared_resources_with_v15':[],'archive_sha256':sha(archive),'runtime_validated':False}
    files={'Addon/'+ARCHIVE:archive,'Addon/'+ARCHIVE+'.stream':b'','Addon/'+ARCHIVE+'.gpu_resources':b'',
        'manifest.json':json.dumps(manifest,indent=2).encode(),'provenance.json':json.dumps(report,indent=2).encode(),
        'INSTALL.txt':(f'Package variant: v15 Addon / {label}\nChoose exactly one Rover ZIP. Install official v15 loader separately.\nNo HUD omits all Rover GUI code; text logs remain enabled.\n\n'+(ROOT/'docs/packaging-channels.md').read_text(encoding='utf-8')).encode('utf-8')}
    out=ROOT/'releases'/package_name('v15',show_hud)
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for path,data in sorted(files.items()):
            info=zipfile.ZipInfo(path,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None and set(z.namelist())==set(files)
        assert bodies(z.read('Addon/'+ARCHIVE))==readback
    report.update(zip_name=out.name,zip_sha256=sha(out.read_bytes()))
    (folder/'package-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for result in results:print(result)
    print('PASS plaintext declaration, unchanged core, no shared loader resources, archive and ZIP integrity')
    print(out);print('SHA256='+report['zip_sha256'])
    return report


def main():
    for show_hud in (True,False):
        build_variant(show_hud)


if __name__=='__main__':main()
