#!/usr/bin/env python3
"""Exercise more than 350 authenticated TCP/TLS links and graceful SIGTERM.

Uses a temporary, unprivileged daemon with no TUN and disposable test keys.
"""

import argparse
import hashlib
import json
import pathlib
import socket
import ssl
import struct
import subprocess
import tempfile
import time


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def read_exact(connection, size):
    result = b""
    while len(result) < size:
        chunk = connection.recv(size - len(result))
        if not chunk:
            raise RuntimeError("peer closed during authentication")
        result += chunk
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="yggdrasil-ng-check-") as directory:
        root = pathlib.Path(directory)
        key, cert = root / "test.pem", root / "test.crt"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "Ed25519", "-out", str(key)],
            check=True,
        )
        subprocess.run(
            [
                "openssl",
                "req",
                "-new",
                "-x509",
                "-key",
                str(key),
                "-out",
                str(cert),
                "-subj",
                "/CN=test",
                "-days",
                "1",
            ],
            check=True,
        )
        public = subprocess.check_output(
            ["openssl", "pkey", "-in", str(key), "-pubout", "-outform", "DER"]
        )[-32:]
        digest = root / "digest"
        digest.write_bytes(hashlib.blake2b(public).digest())
        signature = subprocess.check_output(
            [
                "openssl",
                "pkeyutl",
                "-sign",
                "-rawin",
                "-inkey",
                str(key),
                "-in",
                str(digest),
            ]
        )
        fields = b"".join(
            struct.pack("!HH", kind, len(value)) + value
            for kind, value in [(0, b"\0\0"), (1, b"\0\5"), (2, public), (3, b"\0")]
        )
        body = fields + signature
        metadata = b"meta" + struct.pack("!H", len(body)) + body
        tcp_port, tls_port, admin_port = unused_port(), unused_port(), unused_port()
        config = root / "config.toml"
        config.write_text(
            f'if_name = "none"\nmulticast_interfaces = []\nmax_inbound_links_per_peer = 0\nadmin_listen = "tcp://127.0.0.1:{admin_port}"\nlisten = ["tcp://127.0.0.1:{tcp_port}", "tls://127.0.0.1:{tls_port}"]\n'
        )
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        context.load_cert_chain(cert, key)
        sockets = []
        with (root / "daemon.log").open("w+") as log:
            daemon = subprocess.Popen(
                [args.binary, "-c", str(config)], stdout=log, stderr=log
            )
            try:
                deadline = time.monotonic() + 15
                while True:
                    try:
                        with socket.create_connection(
                            ("127.0.0.1", admin_port), timeout=0.5
                        ):
                            break
                    except OSError:
                        if daemon.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError("test daemon did not start")
                        time.sleep(0.1)
                for index in range(360):
                    connection = socket.create_connection(
                        ("127.0.0.1", tcp_port if index % 2 == 0 else tls_port),
                        timeout=3,
                    )
                    if index % 2:
                        connection = context.wrap_socket(
                            connection, server_hostname="test"
                        )
                    sockets.append(connection)
                    connection.sendall(metadata)
                    header = read_exact(connection, 6)
                    if header[:4] != b"meta":
                        raise RuntimeError("invalid server metadata")
                    read_exact(connection, struct.unpack("!H", header[4:])[0])
                # Wait briefly for the last metadata to be registered, without
                # waiting long enough for our minimal clients to miss keepalives.
                time.sleep(0.2)
                peers = json.loads(
                    subprocess.check_output(
                        [
                            args.binary,
                            "-e",
                            f"tcp://127.0.0.1:{admin_port}",
                            "-j",
                            "getPeers",
                        ]
                    )
                )
                active = [peer for peer in peers["response"]["peers"] if peer.get("up")]
                if len(active) != 360:
                    raise RuntimeError(f"expected 360 active links, got {len(active)}")
                daemon.terminate()
                if daemon.wait(timeout=10) != 0:
                    raise RuntimeError("SIGTERM did not exit cleanly")
                print(
                    "PASS: 360 simultaneous authenticated TCP/TLS links; clean SIGTERM"
                )
            except Exception:
                log.seek(0)
                print(log.read()[-5000:])
                raise
            finally:
                for connection in sockets:
                    connection.close()
                if daemon.poll() is None:
                    daemon.kill()
                    daemon.wait()


if __name__ == "__main__":
    main()
