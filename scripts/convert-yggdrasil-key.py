#!/usr/bin/env python3
"""Convert an age-encrypted Ed25519 PEM to an encrypted NG keypair.

Only ciphertext is written to disk. The old file remains usable for rollback.
"""

import argparse
import ipaddress
import pathlib
import subprocess


def run(argv, data=None):
    return subprocess.run(argv, input=data, stdout=subprocess.PIPE, check=True).stdout


def address(public):
    bits = "".join(f"{byte ^ 255:08b}" for byte in public)
    leading = len(bits) - len(bits.lstrip("1"))
    tail = bits[leading + 1 :][:112].ljust(112, "0")
    raw = bytes([2, leading]) + int(tail, 2).to_bytes(14, "big")
    subnet = bytes([3]) + raw[1:8] + bytes(8)
    return str(ipaddress.IPv6Address(raw)), str(ipaddress.IPv6Address(subnet)) + "/64"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("target", type=pathlib.Path)
    parser.add_argument("--age", default="age")
    parser.add_argument("--identity", required=True)
    parser.add_argument("--recipient", action="append", required=True)
    parser.add_argument("--expected-address")
    args = parser.parse_args()
    if args.target.exists():
        parser.error("target already exists")

    pem = run([args.age, "-d", "-i", args.identity, str(args.source)])
    private = run(["openssl", "pkey", "-outform", "DER"], pem)
    public = run(["openssl", "pkey", "-pubout", "-outform", "DER"], pem)
    private_prefix = bytes.fromhex("302e020100300506032b657004220420")
    public_prefix = bytes.fromhex("302a300506032b6570032100")
    if not (private.startswith(private_prefix) and len(private) == 48):
        raise ValueError("expected an Ed25519 PKCS#8 private key")
    if not (public.startswith(public_prefix) and len(public) == 44):
        raise ValueError("expected an Ed25519 public key")
    key = private[-32:] + public[-32:]
    node_address, subnet = address(public[-32:])
    if args.expected_address and node_address != args.expected_address:
        raise ValueError("derived address differs from the running node")

    command = [args.age, "-a"]
    for recipient in args.recipient:
        command += ["-r", recipient]
    encrypted = run(command, key.hex().encode() + b"\n")
    # Verify both the envelope and the exact keypair before writing ciphertext.
    restored = run([args.age, "-d", "-i", args.identity], encrypted)
    if restored.strip() != key.hex().encode():
        raise ValueError("encrypted key did not round-trip")
    with args.target.open("xb") as target:
        target.write(encrypted)
    print(
        f"{args.target}: address={node_address} subnet={subnet} public_key={public[-32:].hex()}"
    )


if __name__ == "__main__":
    main()
