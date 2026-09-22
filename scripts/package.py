"""Build HUD and No HUD experimental ZIPs; never deploy or launch the game."""
import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path
from build import compile_entry
from lua_host import Lua, literal
from test import ROOT, GAME

# Keep this project's package.py ahead of the archive dependency's namesake.
sys.path.insert(1,str(ROOT.parent/'SentryAimRetention/scripts'))
from archive import resource_hash, make_archive, TYPE, ARCHIVE

LOADER_SHA='4A95D7A056F0A9E01842420883059A380374092145B5D9EC807C14C8CA351568'
CALLBACK_SHA='D07ED04A7F68D588F424D155AFD8F08B1BFC4D946C90FBC5BBBDCADE1EB69123'
CALLBACK='core/wwise/lua/wwise_flow_callbacks'
MODULE='mods/retrox/rover_fire_spread'
VERSION='0.7.10'
PACKAGE_NAME='激光狗索敌优化'


def package_name(channel, show_hud):
    loader_label={'v12':'内置加载器','v14':'内置加载器','v15':'需要额外安装加载器'}[channel]
    return f'{PACKAGE_NAME}-{VERSION}-{channel}-{loader_label}'+('' if show_hud else '-No-HUD')+'.zip'


def sha(data):return hashlib.sha256(data).hexdigest().upper()


def extract(archive):
    magic,types,count=struct.unpack_from('<III',archive)
    assert magic==0xf0000011 and types<100 and count<1000
    result={}
    for index in range(count):
        row=struct.unpack_from('<7Q6I',archive,72+32*types+80*index)
        assert row[1]==TYPE and row[2]+row[7]<=len(archive)
        resource=archive[row[2]:row[2]+row[7]]
        size,version=struct.unpack_from('<II',resource)
        assert version==2 and size+8==len(resource) and resource[8:13]==b'\x1bLJ\x02\x02'
        assert row[0] not in result
        result[row[0]]=resource
    return result


def load_base(show_hud):
    """Resolve the current verified base ZIP, never silently reuse an old core."""
    suffix='' if show_hud else '-no-hud'
    report=json.loads((ROOT/('build/experimental-package-report'+suffix+'.json')).read_text(encoding='utf-8'))
    expected=package_name('v12',show_hud)
    assert report['zip_name']==expected,'Rebuild the current base packages with package.py first'
    assert report['hud']['enabled']==show_hud,'Base HUD variant mismatch'
    path=ROOT/report.get('zip_relative_path','releases/'+expected)
    assert path.name==expected and path.resolve().is_relative_to(ROOT.resolve()),'Unexpected base package path'
    assert sha(path.read_bytes())==report['zip_sha256'],'Base package checksum mismatch'
    return path,report


def build_variant(original, show_hud, internal=False):
    folder=ROOT/'build'
    report_suffix='' if show_hud else '-no-hud'
    label='HUD' if show_hud else 'No HUD'
    code,report=compile_entry(True,show_hud=show_hud)
    if not show_hud:
        assert 'hud' not in report['sources'], 'No HUD must omit the drawing module'
    source='local start=(function()\n'+(ROOT/'src/startup.lua').read_text()+'\nend)()\n'
    source+='start(function() assert(loadstring('+literal(original[8:])+", '@published_bingus_v12'))() end,\n"
    source+='function() assert(loadstring('+literal(code)+", '@rover_fire_spread_"+VERSION.replace('.','_')+report_suffix+"'))() end)\n"
    lua=Lua(GAME/'bin/lua51.dll')
    try:
        bridge=lua.compile(source)
        bridge_path=folder/('startup'+report_suffix+'.luac')
        bridge_path.write_bytes(bridge)
        tests=lua.run('EXPECT_HUD='+('true' if show_hud else 'false')+';ORIGINAL='+literal((folder/'published-loader.luac').as_posix().encode())+';BRIDGE='+literal(bridge_path.as_posix().encode())+';return assert(loadfile('+literal((ROOT/'tests/check_bridge.lua').as_posix().encode())+'))()').decode()
    finally:lua.close()
    resources={resource_hash(MODULE):struct.pack('<II',len(code),2)+code,
               resource_hash(CALLBACK):struct.pack('<II',len(bridge),2)+bridge}
    archive=make_archive(resources)
    assert extract(archive)==resources,'Archive round-trip mismatch'
    report.update({'installable':True,'gameplay_validated':False,'startup_tests':tests,
        'read_layout_evidence':'24826606: rover-policy-20260918-001636/001839; 25327279: rover-policy-20260922-215104',
        'loader_release':'https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v12',
        'loader_zip_sha256':LOADER_SHA,'loader_callback_resource_sha256':CALLBACK_SHA,
        'startup_sha256':sha((ROOT/'src/startup.lua').read_bytes()),
        'archive_sha256':sha(archive),'module':MODULE,
        'target_policy':{'attack_window_seconds':0.4,'history_limit':1,'history_seconds':1,'no_attack_seconds':1.5,'max_lock_seconds':1.5,
            'near_radius':30,
            'player_mark_priority':'build 25327279: newest active own enemy marker intersected with native eligible identity; on normal rotations outranks distance but respects Recent; timeout escape unchanged',
            'preferred':'nearest to departing target among eligible targets absent from recent identity-aware history',
            'near_override':'if departing target is beyond 30m from drone and eligible alternatives exist within 30m inclusive, restrict to near pool before Recent filtering and rank by drone range',
            'all_recent':'oldest observation in selected pool, then selected distance metric',
            'lock_max_duration':'1.5s continuous identified same-target observation across node 6/7 attack-state toggles; reset after committed request or invalid observation; reselect nearest other eligible target ignoring Recent',
            'lock_timeout':'same target without synchronized attack state on node 6/7; choose nearest other eligible target ignoring recent history',
            'distance':'cached departing-target XYZ to candidate XYZ; drone range fallback if target-relative positions unavailable; native scoring if both unavailable. Timeout always uses drone range.',
            'distance_runtime_validated':False},
        'hud':{'enabled':show_hud,'runtime_validated':False,'font_layout':'registered layout font roots' if show_hud else None,'refresh_hz':10 if show_hud else 0,'placement':'top center' if show_hud else None},
        'compatibility_policy':'hash mismatch advisory; runtime signatures and layout checks required',
        'boot_replaced':False,'custom_dlls':0,'native_calls':0,'local_private_build':True})
    description='Own active marked enemy receives priority at normal rotation boundaries on build 25327279; short bursts, Recent and timeout escape remain active. Laser Rover rotation: prefer enemies adjacent to the departing target; prioritize enemies within 30m of Rover when leaving a target beyond 30m. Recent: 1 record / 1 second. After 1.5s without synchronized attack state, or 1.5s on the same identified target across attack-state toggles, request nearest alternative. Normal 0.4s attack rotation takes priority. Includes Bingus Shared Loader v12 bridge. '
    description+=('Live status HUD for testing. ' if show_hud else 'No HUD: no overlay creation or drawing. ')
    description+='Install only one variant. Gameplay stability still requires validation.'
    manifest={'Version':1,'Guid':'209a1d35-17ef-4c55-a163-616bf8f31861','Name':f'{PACKAGE_NAME} {VERSION} v12 内置加载器 ({label})',
        'Description':description,'Options':[{'Name':label,'Description':description,'Include':['data']}]}
    instructions=f'Package variant: v12 / 内置加载器 / {label}\nInstall only one variant; remove/disable the other before switching.\n'
    if not show_hud:
        instructions+='This package omits the HUD module. No overlay is created; text logs and targeting remain enabled.\nHUD instructions below apply only to the HUD variant.\n'
    instructions+='\n'+(ROOT/'INSTALL.txt').read_text(encoding='utf-8')
    files={'data/'+ARCHIVE:archive,'data/'+ARCHIVE+'.stream':b'','data/'+ARCHIVE+'.gpu_resources':b'',
        'manifest.json':json.dumps(manifest,indent=2).encode(),
        'provenance.json':json.dumps(report,indent=2).encode(),
        'INSTALL.txt':instructions.encode('utf-8')}
    out=ROOT/('build/internal-base' if internal else 'releases')/package_name('v12',show_hud)
    out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9)as z:
        for name,data in sorted(files.items()):
            info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    with zipfile.ZipFile(out)as z:
        assert z.testzip()is None and set(z.namelist())==set(files)
        assert extract(z.read('data/'+ARCHIVE))==resources
    report['zip_sha256']=sha(out.read_bytes())
    report['zip_name']=out.name
    report['zip_relative_path']=out.relative_to(ROOT).as_posix()
    (folder/('experimental-package-report'+report_suffix+'.json')).write_text(json.dumps(report,indent=2))
    print(label+': '+tests);print('PASS archive resource round-trip and ZIP integrity');print(out)
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channels',nargs='+',choices=['v12','v14','v15'],default=['v12','v14','v15'])
    args=parser.parse_args();channels=set(args.channels)
    # Validate all fixed inputs before generating any package in the matrix.
    from package_v14 import build_variant as build_v14, LOADER_SHA as V14_SHA
    from package_v15 import build_variant as build_v15, LOADER_SHA as V15_SHA
    folder=ROOT/'build'
    for version,digest in [('v14',V14_SHA),('v15',V15_SHA)]:
        assert sha((folder/f'Bingus-Shared-Loader-{version}.zip').read_bytes())==digest,'Unexpected '+version+' loader input'
    loader=folder/'Bingus-Shared-Loader-v12.zip'
    assert sha(loader.read_bytes())==LOADER_SHA,'Unexpected shared loader input'
    with zipfile.ZipFile(loader)as z:
        archive=z.read('data/'+ARCHIVE)
    original=extract(archive)[resource_hash(CALLBACK)]
    assert sha(original)==CALLBACK_SHA
    (folder/'published-loader.luac').write_bytes(original[8:])
    reports=[build_variant(original,True,internal='v12' not in channels),build_variant(original,False,internal='v12' not in channels)]
    common=set(reports[0]['sources'])-{'hud'}
    assert common==set(reports[1]['sources'])
    assert all(reports[0]['sources'][name]==reports[1]['sources'][name] for name in common)
    assert reports[0]['target_policy']==reports[1]['target_policy']
    print('PASS both variants share identical targeting sources and policy')
    for channel,builder in (('v14',build_v14),('v15',build_v15)):
        if channel not in channels:continue
        for show_hud in (True,False):
            reports.append(builder(show_hud))
    for i,report in enumerate(reports[2:]):
        base=reports[i%2]
        assert report['core_sources']==base['sources'],'Channel changed core source hashes'
        assert report['target_policy']==base['target_policy'],'Channel changed targeting policy'
    release_reports=reports if 'v12' in channels else reports[2:]
    (folder/'package-matrix.json').write_text(json.dumps({
        'version':VERSION,'channels':sorted(channels),'packages':[{k:r[k] for k in ('zip_name','zip_sha256')} for r in release_reports]
    },indent=2),encoding='utf-8')
    print(f'PASS {len(release_reports)} release packages: '+','.join(sorted(channels))+' x HUD/No HUD; shared core verified; no deployment')


if __name__=='__main__':main()
