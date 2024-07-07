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
const boolTrue = BoolValue(value: true)
const boolFalse = BoolValue(value: false)

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
            expectCompressed: boolTrue,
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
            expectCompressed: boolFalse,
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
            expectCompressed: boolTrue,
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
          responseCompressed: boolTrue,
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
          responseCompressed: boolFalse,
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ))
        let (compressed, reply) = await stream.recvMessage2(SimpleResponse)
        doAssert not compressed
        doAssert reply.payload.body.len == 314159
        inc checked
  doAssert checked == 2

const streamingInputCallPath = "/grpc.testing.TestService/StreamingInputCall"

testAsync "client_streaming":
  var checked = false
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(streamingInputCallPath)
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

testAsync "client_compressed_streaming":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    try:
      let stream = client.newGrpcStream(streamingInputCallPath)
      with stream:
        await stream.sendMessage(
          StreamingInputCallRequest(
            expectCompressed: boolTrue,
            payload: Payload(body: newSeq[byte](27182))
          ),
          finish = true
        )
        discard await stream.recvMessage(StreamingInputCallResponse)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == stcInvalidArg
      inc checked
    block:
      let stream = client.newGrpcStream(streamingInputCallPath)
      with stream:
        await stream.sendMessage(
          StreamingInputCallRequest(
            expectCompressed: boolTrue,
            payload: Payload(body: newSeq[byte](27182))
          ),
          compress = true
        )
        await stream.sendMessage(
          StreamingInputCallRequest(
            expectCompressed: boolFalse,
            payload: Payload(body: newSeq[byte](45904))
          ),
          finish = true
        )
        let reply = await stream.recvMessage(StreamingInputCallResponse)
        doAssert reply.aggregatedPayloadSize == 73086
        inc checked
  doAssert checked == 2

const streamingOutputCall = "/grpc.testing.TestService/StreamingOutputCall"

testAsync "server_streaming":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(streamingOutputCall)
    with stream:
      await stream.sendMessage(StreamingOutputCallRequest(
        responseParameters: @[
          ResponseParameters(size: 31415),
          ResponseParameters(size: 9),
          ResponseParameters(size: 2653),
          ResponseParameters(size: 58979),
        ]
      ))
      var sizes = newSeq[int]()
      whileRecvMessages stream:
        let request = await stream.recvMessage(StreamingOutputCallResponse)
        sizes.add request.payload.body.len
      doAssert sizes == @[31415, 9, 2653, 58979]
      inc checked
  doAssert checked == 1

testAsync "server_compressed_streaming":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(streamingOutputCall)
    with stream:
      await stream.sendMessage(StreamingOutputCallRequest(
        responseParameters: @[
          ResponseParameters(size: 31415, compressed: boolTrue),
          ResponseParameters(size: 92653, compressed: boolFalse),
        ]
      ))
      var sizes = newSeq[int]()
      var compr = newSeq[bool]()
      whileRecvMessages stream:
        let (compressed, request) =
          await stream.recvMessage2(StreamingOutputCallResponse)
        sizes.add request.payload.body.len
        compr.add compressed
      doAssert sizes == @[31415, 92653]
      doAssert compr == @[true, false]
      inc checked
  doAssert checked == 1

const fullDuplexCallPath = "/grpc.testing.TestService/FullDuplexCall"

testAsync "ping_pong":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(fullDuplexCallPath)
    with stream:
      let rpsizes = [31415, 9, 2653, 58979]
      let psizes = [27182, 8, 1828, 45904]
      for i in 0 .. 3:
        await stream.sendMessage(
          StreamingOutputCallRequest(
            responseParameters: @[
              ResponseParameters(size: rpsizes[i].int32)
            ],
            payload: Payload(body: newSeq[byte](psizes[i]))
          ),
          finish = i == 3
        )
        let request = await stream.recvMessage(StreamingOutputCallResponse)
        doAssert request.payload.body.len == rpsizes[i]
        inc checked
  doAssert checked == 4
