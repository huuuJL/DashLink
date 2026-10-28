"""Run with the compiled native-relay-smoke Swift binary as the first argument."""
import json
import socket
import subprocess
import sys

def assert_closed(peer):
    try:
        assert peer.recv(1) == b'', 'Rejected peer remained connected'
    except ConnectionResetError:
        pass  # A refused connection may close with a reset instead of FIN.

child = subprocess.Popen([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    config = json.loads(child.stdout.readline())
    address = ('127.0.0.1', config['port'])
    token = config['token'].encode() + b'\n'
    for invalid in [b'wrong-token\n', b'x' * 129]:
        with socket.create_connection(address, timeout=5) as peer:
            peer.sendall(invalid)
            assert_closed(peer)
    for attempt in range(2):
        with socket.create_connection(address, timeout=5) as peer:
            peer.sendall(token[:10])
            peer.sendall(token[10:])
            reply = b''
            while not reply.endswith(b'\n'):
                reply += peer.recv(1)
            assert reply == b'OK\n'
            with socket.create_connection(address, timeout=5) as extra:
                extra.sendall(token)
                assert_closed(extra)
            payload = bytes(range(256)) * 800
            peer.sendall(payload)
            received = b''
            while len(received) < len(payload):
                chunk = peer.recv(1023)
                assert chunk, 'Stream ended before the payload arrived'
                received += chunk
            assert received == payload, 'Relay changed byte ordering or contents'
    print('Native relay passed: token rejection, bounded greeting, fragmented authentication, single peer, byte order, reconnect.')
finally:
    child.terminate()
    child.communicate(timeout=5)
