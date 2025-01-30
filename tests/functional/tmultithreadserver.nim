
import std/asyncdispatch

import ../../src/grpc
import ./pbtypes

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

echo "Serving forever"
run(
  hostname = "127.0.0.1",
  port = Port 8121,
  routes = @[
    (GreeterSayHelloPath, sayHello.GrpcSafeCallback)
  ],
  threads = 8,
  ssl = false
)
