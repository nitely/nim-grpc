# Package

version = "0.1.0"
author = "Esteban Castro Borsani (@nitely)"
description = "Pure Nim gRPC client and server"
license = "MIT"
srcDir = "src"
skipDirs = @["tests", "examples"]

requires "nim >= 2.0.0"
requires "hyperx >= 0.1.20"
requires "protobuf_serialization >= 0.3.0"
requires "zippy >= 0.10.14"

#task test, "Test":
#  exec "nim c -r src/grpc.nim"

task exampleserve, "Example serve":
  exec "nim c -r examples/tls_server.nim"

task exampleclient, "Example client":
  exec "nim c -r examples/tls_client.nim"

task interopserve, "Interop serve":
  exec "nim c -r tests/interop/testserver.nim"

task interoptest, "Interop test":
  exec "nim c -r tests/interop/testclient.nim"
