# Package

version = "0.1.0"
author = "Esteban Castro Borsani (@nitely)"
description = "Pure Nim gRPC client and server"
license = "MIT"
srcDir = "src"
skipDirs = @["tests", "examples"]

requires "nim >= 2.0.0"
requires "hyperx >= 0.1.15"
requires "protobuf_serialization >= 0.3.0"

#task test, "Test":
#  exec "nim c -r src/grpc.nim"
