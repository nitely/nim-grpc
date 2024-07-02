{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

import ../src/grpc/server
import ../src/grpc/utils
import ../src/grpc/protobuf

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

importProto3("hello.proto")

# sayHello(request: HelloRequest): HelloReply
# sayHelloStreamIn(strmIn: HelloRequestStream): HelloReply
# sayHelloStreamOut(request: HelloRequest, strmOut: HelloReplyStream)
# sayHelloStreamInOut(strmIn: HelloRequestStream, strmOut: HelloReplyStream)

# XXX return Optional[T], may recv nothing if stream ends
proc recvMessage[T](strm: GrpcStream, t: typedesc[T]): Future[T] {.async.} =
  let msg = newStringRef()
  await strm.recvMessage(msg)
  result = msg.pbDecode(T)

proc sendMessage[T](strm: GrpcStream, msg: T) {.async.} =
  await strm.sendMessage(msg.pbEncode())

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

when isMainModule:
  proc main() {.async.} =
    echo "Serving forever"
    let server = newServer()
    await server.serve({
      "/helloworld.Greeter/SayHello": sayHello.ViewCallback
    }.newtable)
  waitFor main()
  echo "ok"
