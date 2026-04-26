# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio>=1.60", "protobuf>=4.25"]
# ///
"""Driver: launches the Mojo gRPC server binary, sends requests via Python grpcio, validates."""
import os
import sys
import time
import subprocess
import signal

import grpc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "gen"))
import echo_pb2
import echo_pb2_grpc

HERE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(HERE, "certs", "server.crt")
PORT = int(os.environ.get("MOJO_SERVER_PORT", "50553"))


def main():
    server_bin = os.path.join(HERE, "test_mojo_server")
    if not os.path.exists(server_bin):
        print(f"SKIP: {server_bin} not found (build it first)")
        sys.exit(0)

    # Start the Mojo server
    env = {**os.environ, "MOJO_SERVER_PORT": str(PORT)}
    proc = subprocess.Popen(
        [server_bin],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        cwd=os.path.join(HERE, ".."),
    )

    # Wait for "listening" message
    try:
        for _ in range(100):
            line = proc.stdout.readline().decode().strip()
            if "listening" in line:
                break
            time.sleep(0.05)
        else:
            print("FAIL: Mojo server didn't start")
            proc.kill()
            sys.exit(1)

        # Connect via grpcio
        with open(CERT, "rb") as f:
            crt = f.read()
        creds = grpc.ssl_channel_credentials(root_certificates=crt)
        options = (
            ("grpc.ssl_target_name_override", "localhost"),
            ("grpc.default_authority", "localhost"),
        )
        channel = grpc.secure_channel(f"127.0.0.1:{PORT}", creds, options=options)
        grpc.channel_ready_future(channel).result(timeout=5.0)
        stub = echo_pb2_grpc.EchoStub(channel)

        print("=== Mojo server tests (Python client → Mojo server) ===")
        passed = 0
        failed = 0

        # Test 1: basic echo
        try:
            reply = stub.Ping(echo_pb2.PingRequest(seq=42, payload=b"hello"))
            assert reply.seq == 42, f"seq mismatch: {reply.seq}"
            assert reply.payload == b"hello", f"payload mismatch: {reply.payload}"
            print("  PASS echo round-trip (seq=42, payload='hello')")
            passed += 1
        except Exception as e:
            print(f"  FAIL echo round-trip: {e}")
            failed += 1

        # Test 2: multiple requests on same connection
        try:
            for i in range(10):
                reply = stub.Ping(echo_pb2.PingRequest(seq=i, payload=b"x" * 64))
                assert reply.seq == i, f"seq mismatch at i={i}: {reply.seq}"
            print("  PASS 10 sequential requests on same connection")
            passed += 1
        except Exception as e:
            print(f"  FAIL sequential requests: {e}")
            failed += 1

        # Test 3: empty payload
        try:
            reply = stub.Ping(echo_pb2.PingRequest(seq=99, payload=b""))
            assert reply.seq == 99
            print("  PASS empty payload")
            passed += 1
        except Exception as e:
            print(f"  FAIL empty payload: {e}")
            failed += 1

        channel.close()
        print(f"\n{passed} passed, {failed} failed")
        if failed > 0:
            sys.exit(1)

    finally:
        proc.terminate()
        proc.wait(timeout=5)


if __name__ == "__main__":
    main()
