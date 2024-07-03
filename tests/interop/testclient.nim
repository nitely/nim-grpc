## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
##
## Note the enum types were removed in the proto files
## because the protobuf lib lacks support for them, an int32 is used instead

{.define: ssl.}

import std/asyncdispatch
import std/tables

import ../../src/grpc/client

importProto3("empty.proto")
importProto3("messages.proto")

template testAsync(name: string, body: untyped): untyped =
  (proc () = 
    echo "test " & name
    var checked = false
    proc test() {.async.} =
      body
      checked = true
    waitFor test()
    doAssert not hasPendingOperations()
    doAssert checked
  )()

const localHost = "127.0.0.1"
const localPort = Port 4443

testAsync "empty_unary":
  var checked = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(
      "/grpc.testing.TestService/EmptyCall"
    )
    with stream:
      await stream.sendMessage(Empty())
      discard await stream.recvMessage(Empty)
      checked = true
  doAssert checked

testAsync "large_unary":
  var checked = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(
      "/grpc.testing.TestService/UnaryCall"
    )
    with stream:
      await stream.sendMessage(SimpleRequest(
        responseSize: 314159,
        payload: Payload(body: newSeq[byte](271828))
      ))
      let reply = await stream.recvMessage(SimpleResponse)
      doAssert reply.payload.body.len == 314159
      checked = true
  doAssert checked