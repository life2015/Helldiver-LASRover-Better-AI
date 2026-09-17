"""Build a local experimental ZIP; never deploy or launch the game."""
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path
from build import compile_entry
from lua_host import Lua, literal
from test import ROOT, GAME

sys.path.insert(0,str(ROOT.parent/'SentryAimRetention/scripts'))
from archive import resource_hash, make_archive, TYPE, ARCHIVE

LOADER_SHA='4A95D7A056F0A9E01842420883059A380374092145B5D9EC807C14C8CA351568'
CALLBACK_SHA='D07ED04A7F68D588F424D155AFD8F08B1BFC4D946C90FBC5BBBDCADE1EB69123'
CALLBACK='core/wwise/lua/wwise_flow_callbacks'
MODULE='mods/retrox/rover_fire_spread'


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


def main():
    folder=ROOT/'build'
    loader=folder/'Bingus-Shared-Loader-v12.zip'
    assert sha(loader.read_bytes())==LOADER_SHA,'Unexpected shared loader input'
    with zipfile.ZipFile(loader)as z:
        main=z.read('data/'+ARCHIVE)
    original=extract(main)[resource_hash(CALLBACK)]
    assert sha(original)==CALLBACK_SHA
    (folder/'published-loader.luac').write_bytes(original[8:])
    code,report=compile_entry(True)
    source='local start=(function()\n'+(ROOT/'src/startup.lua').read_text()+'\nend)()\n'
    source+='start(function() assert(loadstring('+literal(original[8:])+", '@published_bingus_v12'))() end,\n"
    source+='function() assert(loadstring('+literal(code)+", '@rover_fire_spread_0_3'))() end)\n"
    lua=Lua(GAME/'bin/lua51.dll')
    try:
        bridge=lua.compile(source)
        (folder/'startup.luac').write_bytes(bridge)
        tests=lua.run('ORIGINAL='+literal((folder/'published-loader.luac').as_posix().encode())+';BRIDGE='+literal((folder/'startup.luac').as_posix().encode())+';return assert(loadfile('+literal((ROOT/'tests/check_bridge.lua').as_posix().encode())+'))()').decode()
    finally:lua.close()
    resources={resource_hash(MODULE):struct.pack('<II',len(code),2)+code,
               resource_hash(CALLBACK):struct.pack('<II',len(bridge),2)+bridge}
    archive=make_archive(resources)
    assert extract(archive)==resources,'Archive round-trip mismatch'
    report.update({'installable':True,'gameplay_validated':False,'startup_tests':tests,
        'read_layout_evidence':'rover-policy-20260918-001636 and rover-policy-20260918-001839',
        'loader_release':'https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v12',
        'loader_zip_sha256':LOADER_SHA,'loader_callback_resource_sha256':CALLBACK_SHA,
        'startup_sha256':sha((ROOT/'src/startup.lua').read_bytes()),
        'archive_sha256':sha(archive),'module':MODULE,
        'boot_replaced':False,'custom_dlls':0,'native_calls':0,'local_private_build':True})
    description='Experimental laser Rover target rotation, approximate 0.4s attack window. Includes Bingus Shared Loader v12 startup bridge; give this package winning startup priority. In-game effect not yet verified.'
    manifest={'Version':1,'Guid':'209a1d35-17ef-4c55-a163-616bf8f31861','Name':'Rover Fire Spread - Experimental 0.3',
        'Description':description,'Options':[{'Name':'Experimental 0.3','Description':description,'Include':['data']}]}
    files={'data/'+ARCHIVE:archive,'data/'+ARCHIVE+'.stream':b'','data/'+ARCHIVE+'.gpu_resources':b'',
        'manifest.json':json.dumps(manifest,indent=2).encode(),
        'provenance.json':json.dumps(report,indent=2).encode(),
        'INSTALL.txt':(ROOT/'INSTALL.txt').read_bytes()}
    out=ROOT/'releases/Rover-Fire-Spread-Experimental-0.3.zip';out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9)as z:
        for name,data in sorted(files.items()):
            info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    with zipfile.ZipFile(out)as z:
        assert z.testzip()is None and set(z.namelist())==set(files)
        assert extract(z.read('data/'+ARCHIVE))==resources
    report['zip_sha256']=sha(out.read_bytes())
    report['zip_name']=out.name
    (folder/'experimental-package-report.json').write_text(json.dumps(report,indent=2))
    print(tests);print('PASS archive resource round-trip and ZIP integrity');print(out)


if __name__=='__main__':main()
