## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
##
## Note the enum types were removed in the proto files
## because the protobuf lib lacks support for them, an int32 is used instead

{.define: ssl.}

import std/asyncdispatch

import ../../src/grpc/client
import ./pbtypes

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

testAsync "client_compressed_unary":
  # there is no access to the message bit flag,
  # so this verifies nothing.
  var checked = false
  var checked2 = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(
      "/grpc.testing.TestService/UnaryCall"
    )
    with stream:
      await stream.sendMessage(
        SimpleRequest(
          expectCompressed: BoolValue(value: false),
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ),
        compress = false
      )
      let reply = await stream.recvMessage(SimpleResponse)
      doAssert reply.payload.body.len == 314159
      checked = true
    let stream2 = client.newGrpcStream(
      "/grpc.testing.TestService/UnaryCall"
    )
    with stream2:
      await stream2.sendMessage(
        SimpleRequest(
          expectCompressed: BoolValue(value: true),
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ),
        compress = true
      )
      let reply = await stream2.recvMessage(SimpleResponse)
      doAssert reply.payload.body.len == 314159
      checked2 = true
  doAssert checked
  doAssert checked2

testAsync "server_compressed_unary":
  # there is no access to the message bit flag,
  # so this verifies nothing.
  var checked = false
  var checked2 = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(
      "/grpc.testing.TestService/UnaryCall"
    )
    with stream:
      await stream.sendMessage(SimpleRequest(
        responseCompressed: BoolValue(value: true),
        responseSize: 314159,
        payload: Payload(body: newSeq[byte](271828))
      ))
      let reply = await stream.recvMessage(SimpleResponse)
      doAssert reply.payload.body.len == 314159
      checked = true
    let stream2 = client.newGrpcStream(
      "/grpc.testing.TestService/UnaryCall"
    )
    with stream2:
      await stream2.sendMessage(SimpleRequest(
        responseCompressed: BoolValue(value: false),
        responseSize: 314159,
        payload: Payload(body: newSeq[byte](271828))
      ))
      let reply = await stream2.recvMessage(SimpleResponse)
      doAssert reply.payload.body.len == 314159
      checked2 = true
  doAssert checked
  doAssert checked2

testAsync "client_streaming":
  var checked = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(
      "/grpc.testing.TestService/StreamingInputCall"
    )
    with stream:
      let psizes = [27182, 8, 1828, 45904]
      for i, psize in pairs psizes:
        await stream.sendMessage(
          StreamingInputCallRequest(
            payload: Payload(body: newSeq[byte](psize))
          ),
          finish = i == psizes.len-1
        )
      let reply = await stream.recvMessage(StreamingInputCallResponse)
      doAssert reply.aggregatedPayloadSize == 74922
      checked = true
  doAssert checked
