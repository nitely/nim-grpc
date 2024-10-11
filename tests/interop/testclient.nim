## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
##
## Note the enum types were removed in the proto files
## because the protobuf lib lacks support for them, an int32 is used instead

{.define: ssl.}

from std/strutils import contains
import std/asyncdispatch

from ../../src/grpc/clientserver import recvMessage2
import ../../src/grpc/client
import ../../src/grpc/errors
import ./pbtypes

const testCompression = defined(grpcTestCompression)
const testSsl = not defined(grpcTestNoSsl)

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
const localPort = if testSsl: Port 8223 else: Port 8333
const boolTrue = BoolValue(value: true)
const boolFalse = BoolValue(value: false)

testAsync "empty_unary":
  var checked = false
  var client = newClient(localHost, localPort, ssl = testSsl)
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
  var client = newClient(localHost, localPort, ssl = testSsl)
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

when testCompression:
  testAsync "client_compressed_unary":
    var checked = 0
    var client = newClient(localHost, localPort, ssl = testSsl)
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
        let stream = client.newGrpcStream(unaryCallPath, compress = true)
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

when testCompression:
  testAsync "server_compressed_unary":
    var checked = 0
    var client = newClient(localHost, localPort, ssl = testSsl)
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
  var client = newClient(localHost, localPort, ssl = testSsl)
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

when testCompression:
  testAsync "client_compressed_streaming":
    var checked = 0
    var client = newClient(localHost, localPort, ssl = testSsl)
    with client:
      try:
        let stream = client.newGrpcStream(streamingInputCallPath, compress = true)
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
        let stream = client.newGrpcStream(streamingInputCallPath, compress = true)
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
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    let stream = client.newGrpcStream(streamingOutputCall)
    with stream:
      await stream.sendMessage(
        StreamingOutputCallRequest(
          responseParameters: @[
            ResponseParameters(size: 31415),
            ResponseParameters(size: 9),
            ResponseParameters(size: 2653),
            ResponseParameters(size: 58979),
          ]
        ),
        finish = true
      )
      var sizes = newSeq[int]()
      whileRecvMessages stream:
        let request = await stream.recvMessage(StreamingOutputCallResponse)
        sizes.add request.payload.body.len
      doAssert sizes == @[31415, 9, 2653, 58979]
      inc checked
  doAssert checked == 1

when testCompression:
  testAsync "server_compressed_streaming":
    var checked = 0
    var client = newClient(localHost, localPort, ssl = testSsl)
    with client:
      let stream = client.newGrpcStream(streamingOutputCall)
      with stream:
        await stream.sendMessage(
          StreamingOutputCallRequest(
            responseParameters: @[
              ResponseParameters(size: 31415, compressed: boolTrue),
              ResponseParameters(size: 92653, compressed: boolFalse),
            ]
          ),
          finish = true
        )
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
  var client = newClient(localHost, localPort, ssl = testSsl)
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
        let reply = await stream.recvMessage(StreamingOutputCallResponse)
        doAssert reply.payload.body.len == rpsizes[i]
        inc checked
  doAssert checked == 4

testAsync "empty_stream":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    let stream = client.newGrpcStream(fullDuplexCallPath)
    with stream:
      await stream.sendEnd()
      whileRecvMessages stream:
        discard await stream.recvMessage(StreamingOutputCallResponse)
        doAssert false
      inc checked
  doAssert checked == 1

const xInitialKey = "x-grpc-test-echo-initial"
const xInitialValue = "test_initial_metadata_value"
const xTrailingKey = "x-grpc-test-echo-trailing-bin"
const xTrailingValue = "0xababab"

proc sendMetadata(strm: GrpcStream) {.async.} =
  var headers = strm.headersOut
  headers[].add (xInitialKey, xInitialValue)
  headers[].add (xTrailingKey, xTrailingValue)
  await strm.sendHeaders(headers)

testAsync "custom_metadata":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    block:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMetadata()
        await stream.sendMessage(SimpleRequest(
          responseSize: 314159,
          payload: Payload(body: newSeq[byte](271828))
        ))
        let reply = await stream.recvMessage(SimpleResponse)
        doAssert reply.payload.body.len == 314159
        doAssert xInitialKey & ": " & xInitialValue in stream.headers[]
        doAssert xTrailingKey notin stream.headers[]
        inc checked
      # XXX wait for trailers
      doAssert xTrailingKey & ": " & xTrailingValue in stream.headers[]
      inc checked
    block:
      let stream = client.newGrpcStream(fullDuplexCallPath)
      with stream:
        await stream.sendMetadata()
        await stream.sendMessage(
          StreamingOutputCallRequest(
            responseParameters: @[
              ResponseParameters(size: 314159'i32)
            ],
            payload: Payload(body: newSeq[byte](271828))
          )
        )
        await stream.sendEnd()
        let reply = await stream.recvMessage(StreamingOutputCallResponse)
        doAssert reply.payload.body.len == 314159
        doAssert xInitialKey & ": " & xInitialValue in stream.headers[]
        doAssert xTrailingKey notin stream.headers[]
        inc checked
      # XXX wait for trailers
      doAssert xTrailingKey & ": " & xTrailingValue in stream.headers[]
      inc checked
  doAssert checked == 4

testAsync "status_code_and_message":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(SimpleRequest(
          responseStatus: EchoStatus(code: 2, message: "test status message")
        ))
        discard await stream.recvMessage(SimpleResponse)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == 2.StatusCode
      doAssert err.message == "test status message"
      inc checked
    try:
      let stream = client.newGrpcStream(fullDuplexCallPath)
      with stream:
        await stream.sendMetadata()
        await stream.sendMessage(
          StreamingOutputCallRequest(
            responseStatus: EchoStatus(code: 2, message: "test status message")
          )
        )
        await stream.sendEnd()
        discard await stream.recvMessage(StreamingOutputCallResponse)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == 2.StatusCode
      doAssert err.message == "test status message"
      inc checked
  doAssert checked == 2

testAsync "special_status_message":
  let expectedMessage = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(unaryCallPath)
      with stream:
        await stream.sendMessage(SimpleRequest(
          responseStatus: EchoStatus(
            code: 2, message: expectedMessage
          )
        ))
        discard await stream.recvMessage(SimpleResponse)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == 2.StatusCode
      doAssert err.message == expectedMessage
      inc checked
  doAssert checked == 1

testAsync "unimplemented_method":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(
        "/grpc.testing.TestService/UnimplementedCall"
      )
      with stream:
        await stream.sendMessage(Empty())
        discard await stream.recvMessage(Empty)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == stcUnimplemented
      inc checked
  doAssert checked == 1

testAsync "unimplemented_service":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(
        "/grpc.testing.UnimplementedService/UnimplementedCall"
      )
      with stream:
        await stream.sendMessage(Empty())
        discard await stream.recvMessage(Empty)
        doAssert false
    except GrpcResponseError as err:
      doAssert err.code == stcUnimplemented
      inc checked
  doAssert checked == 1

testAsync "cancel_after_begin":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(streamingInputCallPath)
      with stream:
        await stream.sendHeaders()
        await stream.sendCancel()
    except GrpcFailure as err:
      doAssert err.code == stcCancelled, $err.code
      inc checked
  doAssert checked == 1

testAsync "cancel_after_first_response":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(fullDuplexCallPath)
      with stream:
        await stream.sendMessage(StreamingOutputCallRequest(
          responseParameters: @[
            ResponseParameters(size: 31415)
          ],
          payload: Payload(body: newSeq[byte](27182))
        ))
        let reply = await stream.recvMessage(StreamingOutputCallResponse)
        doAssert reply.payload.body.len == 31415
        await stream.sendCancel()
        inc checked
    except GrpcFailure as err:
      doAssert err.code == stcCancelled, $err.code
      inc checked
  doAssert checked == 2

testAsync "timeout_on_sleeping_server":
  var checked = 0
  var client = newClient(localHost, localPort, ssl = testSsl)
  with client:
    try:
      let stream = client.newGrpcStream(
        fullDuplexCallPath,
        timeout = 1,
        timeoutUnit = grpcMsec
      )
      with stream:
        await stream.sendMessage(StreamingOutputCallRequest(
          payload: Payload(body: newSeq[byte](27182))
        ))
        whileRecvMessages stream:
          discard await stream.recvMessage(StreamingOutputCallResponse)
    except GrpcFailure as err:
      doAssert err.code == stcDeadlineEx, $err.code
      inc checked
  doAssert checked == 1
