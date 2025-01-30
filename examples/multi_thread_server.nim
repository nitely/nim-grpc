## non-TLS multi thread example; tls_server is more complete

import std/asyncdispatch
import std/cpuinfo

import ../src/grpc
import ./pbtypes

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

echo "Serving forever"
run(
  hostname = "127.0.0.1",
  port = Port 8115,
  routes = @[
    (GreeterSayHelloPath, sayHello.GrpcSafeCallback)
  ],
  threads = max(1, countProcessors()),
  ssl = false
)
