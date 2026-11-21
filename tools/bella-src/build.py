#!/usr/bin/env python3
"""Dong goi bo cong cu Bella vao <repo>/tools/bella: chuan hoa CRLF + BOM, tinh SHA256, ghi manifest.json va zip cai dat.
Dung: python3 build.py <version> <out_dir>"""
import hashlib, json, os, sys, zipfile

SRC = os.path.dirname(os.path.abspath(__file__))
UPDATE_FILES = ['BellaTools.ps1', 'BellaScan.ps1', 'Update.ps1', 'DriveUpload.ps1', 'HUONG_DAN.txt']
INSTALL_ONLY = ['Install.ps1', 'CaiDat.bat']

def norm(name):
    raw = open(os.path.join(SRC, name), 'rb').read()
    txt = raw.decode('utf-8-sig').replace('\r\n', '\n').replace('\n', '\r\n')
    bom = b'' if name.endswith('.bat') else b'\xef\xbb\xbf'
    return bom + txt.encode('utf-8')

def main(version, out):
    os.makedirs(out, exist_ok=True)
    files = []
    for n in UPDATE_FILES + INSTALL_ONLY:
        data = norm(n)
        open(os.path.join(out, n), 'wb').write(data)
        if n in UPDATE_FILES:
            files.append({'name': n, 'sha256': hashlib.sha256(data).hexdigest().upper()})
    open(os.path.join(out, 'version.txt'), 'w').write(version)
    json.dump({'version': version, 'files': files}, open(os.path.join(out, 'manifest.json'), 'w'), indent=2)
    with zipfile.ZipFile(os.path.join(out, 'MirafilmBella-CaiDat.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        for n in UPDATE_FILES + INSTALL_ONLY + ['version.txt']:
            z.write(os.path.join(out, n), 'MirafilmBella-CaiDat/' + n)
    print('built', version, [f['name'] for f in files])

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
