{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

import ../src/grpc
import ./pbtypes

const localHost = "127.0.0.1"
const localPort = Port 8113
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

proc sayHelloStreamReply(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  for i in 0 .. 2:
    await strm.sendMessage(
      HelloReply(message: "Hello, " & request.name & " " & $i)
    )

proc sayHelloBidiStream(strm: GrpcStream) {.async.} =
  whileRecvMessages strm:
    let request = await strm.recvMessage(HelloRequest)
    await strm.sendMessage(
      HelloReply(message: "Hello, " & request.name)
    )

proc sayHelloBidiStream2(strm: GrpcStream) {.async.} =
  var message = "Hello"
  for _ in 0 .. 2:
    await strm.sendMessage(
      HelloReply(message: message)
    )
    let request = await strm.recvMessage(HelloRequest)
    message = "Hello, " & request.name

proc main() {.async.} =
  echo "Serving forever"
  let server = newServer(localHost, localPort, certFile, keyFile)
  await server.serve({
    "/helloworld.Greeter/SayHello": sayHello.GrpcCallback,
    "/helloworld.Greeter/SayHelloStreamReply": sayHelloStreamReply.GrpcCallback,
    "/helloworld.Greeter/SayHelloBidiStream": sayHelloBidiStream.GrpcCallback,
    "/helloworld.Greeter/SayHelloBidiStream2": sayHelloBidiStream2.GrpcCallback,
  }.newtable)

waitFor main()
