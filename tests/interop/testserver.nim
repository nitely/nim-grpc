## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md

{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

from ../../src/grpc/clientserver import recvMessage2
import ../../src/grpc/server
import ../../src/grpc/utils
import ../../src/grpc/errors
import ../../src/grpc/statuscodes
import ../../src/grpc/headers
import ./pbtypes

const localHost = "127.0.0.1"
const localPort = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

proc echoMetadataInitial(strm: GrpcStream) {.async.} =
  var headersOut = strm.headersOut
  let oldLen = headersOut[].len
  for (nn, vv) in headersIt strm.headers[]:
    if toOpenArray(strm.headers[], nn.a, nn.b) == "x-grpc-test-echo-initial":
      headersOut[].add ("x-grpc-test-echo-initial", strm.headers[][vv])
  if headersOut[].len > oldLen:
    await strm.sendHeaders(headersOut)

proc echoMetadataTrailing(strm: GrpcStream) {.async.} =
  var headersOut = strm.trailersOut(stcOk)
  let oldLen = headersOut[].len
  for (nn, vv) in headersIt strm.headers[]:
    if toOpenArray(strm.headers[], nn.a, nn.b) == "x-grpc-test-echo-trailing-bin":
      headersOut[].add ("x-grpc-test-echo-trailing-bin", strm.headers[][vv])
  if headersOut[].len > oldLen:
    await strm.sendTrailers(headersOut)

proc emptyCall(strm: GrpcStream) {.async.} =
  discard await strm.recvMessage(Empty)
  await strm.sendMessage(Empty())

proc unaryCall(strm: GrpcStream) {.async.} =
  await strm.echoMetadataInitial()
  let (compressed, request) = await strm.recvMessage2(SimpleRequest)
  check compressed == request.expectCompressed.value,
    newGrpcFailure(stcInvalidArg)
  await strm.sendMessage(
    SimpleResponse(
      payload: Payload(body: newSeq[byte](request.responseSize))
    ),
    compress = request.responseCompressed.value
  )
  await strm.echoMetadataTrailing()

proc streamingInputCall(strm: GrpcStream) {.async.} =
  var size = 0
  whileRecvMessages strm:
    let (compressed, request) = await strm.recvMessage2(StreamingInputCallRequest)
    check compressed == request.expectCompressed.value,
      newGrpcFailure(stcInvalidArg)
    size += request.payload.body.len
  await strm.sendMessage(StreamingInputCallResponse(
    aggregatedPayloadSize: size.int32
  ))

proc streamingOutputCall(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(StreamingOutputCallRequest)
  for rp in request.responseParameters:
    await strm.sendMessage(
      StreamingOutputCallResponse(
        payload: Payload(body: newSeq[byte](rp.size))
      ),
      compress = rp.compressed.value
    )

proc fullDuplexCall(strm: GrpcStream) {.async.} =
  await strm.echoMetadataInitial()
  whileRecvMessages strm:
    let request = await strm.recvMessage(StreamingOutputCallRequest)
    for rp in request.responseParameters:
      await strm.sendMessage(StreamingOutputCallResponse(
        payload: Payload(body: newSeq[byte](rp.size))
      ))
  await strm.echoMetadataTrailing()

proc main() {.async.} =
  echo "Serving forever"
  let server = newServer(localHost, localPort, certFile, keyFile)
  await server.serve({
    "/grpc.testing.TestService/EmptyCall": emptyCall.GrpcCallback,
    "/grpc.testing.TestService/UnaryCall": unaryCall.GrpcCallback,
    "/grpc.testing.TestService/StreamingInputCall": streamingInputCall.GrpcCallback,
    "/grpc.testing.TestService/StreamingOutputCall": streamingOutputCall.GrpcCallback,
    "/grpc.testing.TestService/FullDuplexCall": fullDuplexCall.GrpcCallback,
  }.newtable)

waitFor main()
