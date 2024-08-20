# Package

version = "0.1.4"
author = "Esteban Castro Borsani (@nitely)"
description = "Pure Nim gRPC client and server"
license = "MIT"
srcDir = "src"
skipDirs = @["tests", "examples"]

requires "nim >= 2.0.0"
requires "hyperx >= 0.1.29"
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
  exec "nim c -r -d:grpcTestCompression tests/interop/testclient.nim"

task interoptest2, "Interop test without compression":
  # go server does not support compression tests
  exec "nim c -r tests/interop/testclient.nim"

task interopserveinsec, "Interop serve insecure":
  exec "nim c -r -d:grpcTestNoSsl tests/interop/testserver.nim"

task interoptestinsec, "Interop test insecure":
  exec "nim c -r -d:grpcTestNoSsl -d:grpcTestCompression tests/interop/testclient.nim"

task interoptestinsec2, "Interop test insecure":
  exec "nim c -r -d:grpcTestNoSsl tests/interop/testclient.nim"

task gointeropserve, "Go interop serve":
  # GRPC_GO_LOG_SEVERITY_LEVEL=info
  echo "Go serve forever"
  exec "./go_server --use_tls --tls_cert_file $HYPERX_TEST_CERTFILE --tls_key_file $HYPERX_TEST_KEYFILE --port 8223"

task gointeroptest, "Go interop test":
  template goTest(testName: string): untyped =
    echo "Go test: " & testName
    exec "./go_client --use_tls --server_port 8223 --test_case " & testName
  goTest "empty_unary"
  goTest "large_unary"
  goTest "client_streaming"
  goTest "server_streaming"
  goTest "ping_pong"
  goTest "empty_stream"
  goTest "custom_metadata"
  goTest "status_code_and_message"
  goTest "special_status_message"
  goTest "unimplemented_method"
  goTest "unimplemented_service"
  goTest "cancel_after_begin"
  goTest "cancel_after_first_response"
  goTest "timeout_on_sleeping_server"

task gointeropserveinsec, "Go interop serve insecure":
  echo "Go serve forever"
  exec "./go_server --port 8333"

task gointeroptestinsec, "Go interop test insecure":
  template goTest(testName: string): untyped =
    echo "Go test: " & testName
    exec "./go_client --server_port 8333 --test_case " & testName
  goTest "empty_unary"
  goTest "large_unary"
  goTest "client_streaming"
  goTest "server_streaming"
  goTest "ping_pong"
  goTest "empty_stream"
  goTest "custom_metadata"
  goTest "status_code_and_message"
  goTest "special_status_message"
  goTest "unimplemented_method"
  goTest "unimplemented_service"
  goTest "cancel_after_begin"
  goTest "cancel_after_first_response"
  goTest "timeout_on_sleeping_server"
