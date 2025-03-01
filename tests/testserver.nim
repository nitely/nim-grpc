{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch

import ../src/grpc
import ./pbtypes

const localHost = "127.0.0.1"
const localPort = Port 8114
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

proc testHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

proc testHelloUni(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  for i in 0 .. 9:
    await strm.sendMessage(
      HelloReply(message: "Hello, " & request.name & " " & $i)
    )

proc testHelloBidi(strm: GrpcStream) {.async.} =
  whileRecvMessages strm:
    let request = await strm.recvMessage(HelloRequest)
    await strm.sendMessage(
      HelloReply(message: "Hello, " & request.name)
    )

proc main() {.async.} =
  echo "Serving forever"
  let server = newServer(localHost, localPort, certFile, keyFile)
  await server.serve(@[
    (GreeterTestHelloPath, testHello.GrpcCallback),
    (GreeterTestHelloUniPath, testHelloUni.GrpcCallback),
    (GreeterTestHelloBidiPath, testHelloBidi.GrpcCallback),
  ])

waitFor main()
