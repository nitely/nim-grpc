## Echo server

{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/streams

import pkg/protobuf
import pkg/hyperx/server

import ../src/grpc/utils

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

const protoDef = """
syntax = "proto3";

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
"""
parseProto(protoDef)

proc processStream(strm: ClientStream) {.async.} =
  withStream strm:
    let data = newStringRef()
    await strm.recvHeaders(data)
    await strm.sendHeaders(
      newSeqRef(@[
        (":status", "200"),
        ("grpc-encoding", "identity"),
        ("grpc-accept-encoding", "identity"),
        ("content-type", "application/grpc+proto")
      ]),
      finish = false
    )
    data[].setLen 0
    while not strm.recvEnded:  # XXX remove
      await strm.recvBody(data)
    let request = data[].decode().readHelloRequest()
    var name = ""
    if request.has(name):
      name = request.name
    let reply = new HelloReply
    reply.message = "Hello, " & name
    await strm.sendBody(newStringRef(encode(reply)), finish = false)
    await strm.sendHeaders(
      newSeqRef(@[
        ("grpc-status", "0")
      ]),
      finish = true
    )

proc processStreamHandler(strm: ClientStream) {.async.} =
  try:
    await processStream(strm)
  except HyperxStrmError as err:
    debugEcho err.msg
  except HyperxConnError as err:
    debugEcho err.msg

proc processClient(client: ClientContext) {.async.} =
  withClient client:
    while client.isConnected:
      let strm = await client.recvStream()
      asyncCheck processStreamHandler(strm)

proc processClientHandler(client: ClientContext) {.async.} =
  try:
    await processClient(client)
  except HyperxConnError as err:
    debugEcho err.msg

proc serve*(server: ServerContext) {.async.} =
  withServer server:
    while server.isConnected:
      let client = await server.recvClient()
      asyncCheck processClientHandler(client)

proc newServer*(): ServerContext =
  newServer(
    localHost, localPort, certFile, keyFile
  )

when isMainModule:
  proc main() {.async.} =
    echo "Serving forever"
    var server = newServer()
    await server.serve()
  waitFor main()
  echo "ok"
