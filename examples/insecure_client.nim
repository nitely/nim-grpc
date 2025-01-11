## non-TLS example; tls_client is more complete

import std/asyncdispatch

import ../src/grpc
import ./pbtypes

proc sayHello(client: ClientContext) {.async.} =
  let stream = client.newGrpcStream(GreeterSayHelloPath)
  with stream:
    await stream.sendMessage(HelloRequest(name: "you"))
    let reply = await stream.recvMessage(HelloReply)
    doAssert reply.message == "Hello, you"

proc main {.async.} =
  let client = newClient("127.0.0.1", Port 8115, ssl = false)
  with client:
    await client.sayHello()
  echo "ok"

waitFor main()
