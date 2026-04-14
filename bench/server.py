# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio>=1.60", "protobuf>=4.25"]
# ///
"""Local TLS gRPC echo server for benchmarking."""
import os
import sys
import signal
from concurrent import futures

import grpc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "gen"))
import echo_pb2
import echo_pb2_grpc
import heavy_pb2
import heavy_pb2_grpc

HERE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(HERE, "certs", "server.crt")
KEY = os.path.join(HERE, "certs", "server.key")


class EchoServicer(echo_pb2_grpc.EchoServicer):
    def Ping(self, request, context):
        return echo_pb2.PingReply(seq=request.seq, payload=request.payload)


class HeavyServicer(heavy_pb2_grpc.HeavyServicer):
    def Echo(self, request, context):
        return request


def main():
    port = int(os.environ.get("BENCH_PORT", "50443"))
    server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=8),
        options=[
            ("grpc.so_reuseport", 0),
            ("grpc.max_concurrent_streams", 100),
        ],
    )
    echo_pb2_grpc.add_EchoServicer_to_server(EchoServicer(), server)
    heavy_pb2_grpc.add_HeavyServicer_to_server(HeavyServicer(), server)

    with open(KEY, "rb") as f:
        key = f.read()
    with open(CERT, "rb") as f:
        crt = f.read()
    creds = grpc.ssl_server_credentials([(key, crt)])
    server.add_secure_port(f"127.0.0.1:{port}", creds)
    server.start()
    print(f"server listening on 127.0.0.1:{port}", flush=True)

    def stop(*_):
        server.stop(0)
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server.wait_for_termination()


if __name__ == "__main__":
    main()
