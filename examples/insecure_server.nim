## non-TLS example; tls_server is more complete

import std/asyncdispatch

import ../src/grpc
import ./pbtypes

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

proc main {.async.} =
  echo "Serving forever"
  let server = newServer("127.0.0.1", Port 8115, ssl = false)
  await server.serve(@[
    (GreeterSayHelloPath, sayHello.GrpcCallback)
  ])

#waitFor main()
let mfut = main()
while true:
  poll(0)
mfut.read()
