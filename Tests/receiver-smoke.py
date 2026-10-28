"""Loopback-only receiver integration check. Uses a synthetic key, never a real accessory identity."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import re
import urllib.request
from urllib.parse import urljoin

app, root = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
root.mkdir(parents=True, exist_ok=True)
identity = root / 'identity' / 'offline-mfi'
identity.mkdir(parents=True, exist_ok=True)
def openssl(*args):
    subprocess.run(['/usr/bin/openssl', *map(str,args)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
openssl('ecparam','-name','prime256v1','-genkey','-noout','-out',root/'test.pem')
openssl('pkcs8','-topk8','-nocrypt','-in',root/'test.pem','-outform','DER','-out',identity/'identity.pk8')
openssl('req','-new','-x509','-key',root/'test.pem','-subj','/CN=DashLink Local Test Only','-days','1','-out',root/'cert.pem')
openssl('crl2pkcs7','-nocrl','-certfile',root/'cert.pem','-outform','DER','-out',identity/'certificate.p7b')
engine = app/'Contents/Resources/engine'
token = 'local-smoke-test-token'
args = [str(engine/'runtime/bin/java'),'-Dorg.slf4j.simpleLogger.defaultLogLevel=warn','-cp',str(engine/'lib/*'),
        'com.playport.server.MainKt','--desktop','--http','--bind','127.0.0.1','--airplay-port','17001',
        '--http-port','18742','--identity-dir',str(root/'identity'),'--state-dir',str(root/'state'),'--mdns','jmdns']
with (root/'receiver.log').open('w') as log:
    process = subprocess.Popen(args,cwd=engine,stdin=subprocess.PIPE,stdout=log,stderr=log)
    try:
        process.stdin.write((json.dumps({'ssid':'TEST_ONLY','password':'private-wifi-test','token':token})+'\n').encode())
        process.stdin.flush()
        for attempt in range(100):
            if process.poll() is not None: raise RuntimeError('Receiver exited; inspect test log.')
            try:
                with urllib.request.urlopen('http://127.0.0.1:18742/api/status',timeout=0.5) as response:
                    state=json.load(response)
                break
            except OSError: time.sleep(0.1)
        else: raise RuntimeError('Receiver did not become ready.')
        assert state['sessionActive'] is False
        page=urllib.request.urlopen('http://127.0.0.1:18742/').read()
        assert b'<html' in page and b'type="module"' in page
        assets = re.findall(r'(?:src|href)="(\./assets/[^\"]+)"', page.decode())
        assert assets, 'Packaged viewer must reference its built assets.'
        for asset in assets:
            with urllib.request.urlopen(urljoin('http://127.0.0.1:18742/', asset)) as response:
                served = response.read()
            assert served == (engine/'web/dist'/asset).read_bytes(), 'Viewer asset did not load: ' + asset
        req=urllib.request.Request('http://127.0.0.1:18742/api/display?token=wrong',data=b'{}',method='POST')
        try: urllib.request.urlopen(req)
        except urllib.error.HTTPError as error: assert error.code == 403
        else: raise AssertionError('Display mutations accepted an invalid token.')
        listeners=subprocess.check_output(['/usr/sbin/lsof','-nP','-a','-p',str(process.pid),'-iTCP:18742','-sTCP:LISTEN']).decode()
        assert '127.0.0.1:18742' in listeners and '*:18742' not in listeners
        assert 'private-wifi-test' not in (root/'receiver.log').read_text()
        process.stdin.close()
        assert process.wait(timeout=12) == 0
        print('Receiver integration passed: packaged viewer and assets served, no false phone session, token rejection, loopback binding, private input, parent-exit cleanup.')
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
