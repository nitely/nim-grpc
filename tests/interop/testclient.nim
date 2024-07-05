## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
##
## Note the enum types were removed in the proto files
## because the protobuf lib lacks support for them, an int32 is used instead

{.define: ssl.}

import std/asyncdispatch

from ../../src/grpc/clientserver import recvMessage2
import ../../src/grpc/client
import ../../src/grpc/errors
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

const unaryCallPath = "/grpc.testing.TestService/UnaryCall"

testAsync "large_unary":
  var checked = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(unaryCallPath)
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
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    try:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(
          SimpleRequest(
            expectCompressed: BoolValue(value: true),
            responseSize: 314159,
            payload: Payload(body: newSeq[byte](271828))
          ),
          compress = false
        )
        # XXX should raise GrpcResponseError here instead of w/e this raises
        discard await stream.recvMessage(SimpleResponse)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == stcInvalidArg
      inc checked
    block:
      let stream = client.newGrpcStream(unaryCallPath)
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
        inc checked
    block:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(
          SimpleRequest(
            expectCompressed: BoolValue(value: true),
            responseSize: 314159,
            payload: Payload(body: newSeq[byte](271828))
          ),
          compress = true
        )
        let reply = await stream.recvMessage(SimpleResponse)
        doAssert reply.payload.body.len == 314159
        inc checked
  doAssert checked == 3

testAsync "server_compressed_unary":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    block:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(SimpleRequest(
          responseCompressed: BoolValue(value: true),
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ))
        let (compressed, reply) = await stream.recvMessage2(SimpleResponse)
        doAssert compressed
        doAssert reply.payload.body.len == 314159
        inc checked
    block:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(SimpleRequest(
          responseCompressed: BoolValue(value: false),
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ))
        let (compressed, reply) = await stream.recvMessage2(SimpleResponse)
        doAssert not compressed
        doAssert reply.payload.body.len == 314159
        inc checked
  doAssert checked == 2

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
