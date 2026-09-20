"""Install or remove only this local test package, while the game is closed."""
import argparse
import csv
import hashlib
import io
import json
import re
import subprocess
import zipfile
from test import ROOT, GAME

ARCHIVE='9ba626afa44a3aa3'
JOURNAL=ROOT/'build/deployment.json'


def sha(data):return hashlib.sha256(data).hexdigest().upper()


def require_closed():
    result=subprocess.run(['tasklist','/FI','IMAGENAME eq helldivers2.exe','/FO','CSV','/NH'],capture_output=True,check=True)
    text=result.stdout.decode(errors='replace')
    if any(row and row[0].lower()=='helldivers2.exe' for row in csv.reader(io.StringIO(text))):
        raise RuntimeError('Helldivers 2 is running. Exit normally before deployment.')


def checked_target(name):
    if not re.fullmatch(ARCHIVE+r'\.patch_\d+(?:\.stream|\.gpu_resources)?',name):
        raise ValueError('Unexpected deployment filename')
    parent=(GAME/'data').resolve()
    target=(parent/name).resolve()
    if target.parent!=parent:raise ValueError('Deployment target escaped game data directory')
    return target


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['install','uninstall'])
    parser.add_argument('--variant',choices=['hud','no-hud'],default='hud',help='Package variant to install (uninstall always follows the existing journal)')
    args=parser.parse_args();require_closed()
    if args.action=='uninstall':
        record=json.loads(JOURNAL.read_text())
        paths=[]
        for name,digest in record['files'].items():
            p=checked_target(name)
            if p.exists():
                if sha(p.read_bytes())!=digest:raise ValueError('Installed file changed; not removing: '+str(p))
                paths.append(p)
        require_closed()
        for p in paths:p.unlink()
        record['status']='removed';JOURNAL.write_text(json.dumps(record,indent=2))
        print('Removed only recorded Rover Fire Spread files');return
    if JOURNAL.exists():
        previous=json.loads(JOURNAL.read_text())
        if previous['status']!='removed':
            raise RuntimeError('A prior installation record exists; inspect it before reinstalling.')
    report_suffix='' if args.variant=='hud' else '-no-hud'
    report=json.loads((ROOT/('build/experimental-package-report'+report_suffix+'.json')).read_text())
    name=report.get('zip_name','Rover-Fire-Spread-Experimental-0.1.zip')
    suffix='' if args.variant=='hud' else '-No-HUD'
    if not re.fullmatch(r'(?:激光狗索敌优化|Rover-Fire-Spread-Experimental)-[\d.]+(?:-v12-内置加载器)?'+suffix+r'\.zip',name):raise ValueError('Unexpected package name')
    if args.variant=='no-hud' and report.get('hud',{}).get('enabled') is not False:
        raise ValueError('No HUD report must explicitly disable HUD')
    package=ROOT/'releases'/name
    if sha(package.read_bytes())!=report['zip_sha256']:raise ValueError('Package checksum mismatch')
    game_hashes={}
    unverified=False
    for relative,expected in [('bin/helldivers2.exe','A09FF52663E73B94FB0CAC0DCB5BA84FFD10ECF44F74A8921AC66AF923988CC3'),
        ('data/game/game.dll','CC75948D90FDFDE259DCB519E9933DB7FFA3CCB281CE4FB89E6B1B011557470C')]:
        actual=sha((GAME/relative).read_bytes());game_hashes[relative]=actual
        if actual!=expected:
            unverified=True
            print('WARNING: unverified game file '+relative+' SHA256='+actual+'; runtime signatures and layout checks remain mandatory.')
    indices=[]
    for path in (GAME/'data').glob(ARCHIVE+'.patch_*'):
        match=re.fullmatch(ARCHIVE+r'\.patch_(\d+)(?:\.stream|\.gpu_resources)?',path.name)
        if match:indices.append(int(match[1]))
    index=max(indices,default=-1)+1
    files={}
    with zipfile.ZipFile(package)as z:
        for suffix in ('','.stream','.gpu_resources'):
            name=ARCHIVE+'.patch_'+str(index)+suffix
            files[name]=z.read('data/'+ARCHIVE+'.patch_0'+suffix)
    for name in files:
        if checked_target(name).exists():raise FileExistsError(name)
    record={'status':'planned','game_directory':str(GAME.resolve()),'package_sha256':sha(package.read_bytes()),
        'variant':args.variant,
        'compatibility':'unverified_build_attempt' if unverified else 'baseline_hash_match','game_hashes':game_hashes,
        'files':{name:sha(data) for name,data in files.items()}}
    JOURNAL.write_text(json.dumps(record,indent=2));require_closed()
    created=[]
    try:
        for name,data in files.items():
            p=checked_target(name)
            with p.open('xb')as out:created.append(p);out.write(data)
        for p in created:
            if sha(p.read_bytes())!=record['files'][p.name]:raise ValueError('Copy verification failed')
    except Exception:
        # Only paths created by this operation are eligible for rollback.
        for p in created:
            if p.exists() and sha(p.read_bytes())==record['files'][p.name]:p.unlink()
        record['status']='incomplete';JOURNAL.write_text(json.dumps(record,indent=2));raise
    record['status']='installed';JOURNAL.write_text(json.dumps(record,indent=2))
    print(json.dumps(record,indent=2))


if __name__=='__main__':main()
