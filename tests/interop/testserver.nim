## Interop tests, see:
## https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md

{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

import ../../src/grpc/server
import ../../src/grpc/utils
import ./pbtypes

const localHost = "127.0.0.1"
const localPort = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

proc emptyCall(strm: GrpcStream) {.async.} =
  discard await strm.recvMessage(Empty)
  await strm.sendMessage(Empty())

proc unaryCall(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(SimpleRequest)
  await strm.sendMessage(
    SimpleResponse(
      payload: Payload(body: newSeq[byte](request.responseSize))
    ),
    compress = request.responseCompressed.value
  )

proc streamingInputCall(strm: GrpcStream) {.async.} =
  var size = 0
  whileRecvMessages strm:
    let request = await strm.recvMessage(StreamingInputCallRequest)
    size += request.payload.body.len
  await strm.sendMessage(StreamingInputCallResponse(
    aggregatedPayloadSize: size.int32
  ))

proc main() {.async.} =
  echo "Serving forever"
  let server = newServer(localHost, localPort, certFile, keyFile)
  await server.serve({
    "/grpc.testing.TestService/EmptyCall": emptyCall.GrpcCallback,
    "/grpc.testing.TestService/UnaryCall": unaryCall.GrpcCallback,
    "/grpc.testing.TestService/StreamingInputCall": streamingInputCall.GrpcCallback,
  }.newtable)

waitFor main()
