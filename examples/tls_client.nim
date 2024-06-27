{.define: ssl.}

import std/asyncdispatch
import std/streams

import pkg/protobuf

import ../src/grpc/client
import ../src/grpc/utils

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

proc sayHello(
  client: ClientContext, request: HelloRequest
): Future[HelloReply] {.async.} =
  let data = await client.get(
    newStringRef("/helloworld.Greeter/SayHello"),
    newStringRef(encode(request))
  )
  result = data[].decode().readHelloReply()

proc sayHelloStreamReply(client: ClientContext): GrpcStream =
  client.newGrpcStream(
    newStringRef("/helloworld.Greeter/SayHelloStreamReply")
  )

proc sayHelloBidiStream(client: ClientContext): GrpcStream =
  client.newGrpcStream(
    newStringRef("/helloworld.Greeter/SayHelloBidiStream")
  )

proc helloRequest(
  strm: GrpcStream,
  request: HelloRequest,
  finish = false
) {.async.} =
  await strm.sendBody(
    newStringRef(encode(request)), finish
  )

proc helloReply(strm: GrpcStream): Future[HelloReply] {.async.} =
  let data = newStringRef()
  await strm.recvBody(data)
  result = data[].decode().readHelloReply()

proc main() {.async.} =
  #var client = newClient("127.0.0.1", Port 50051)
  var client = newClient("127.0.0.1", Port 4443)
  with client:
    block:
      echo "Simple request"
      let request = new HelloRequest
      request.name = "you"
      let reply = await client.sayHello(request)
      if reply.has(message):
        echo reply.message
    when false:
      echo "Stream reply"
      let stream = client.sayHelloStreamReply()
      with stream:
        let request = new HelloRequest
        request.name = "you"
        await stream.helloRequest(request, finish = true)
        while not stream.recvEnded:
          let reply = await stream.helloReply()
          if reply.has(message):
            echo reply.message
    when false:
      echo "Bidirectional stream"
      let stream = client.sayHelloBidiStream()
      with stream:
        for i in 0 .. 2:
          let request = new HelloRequest
          request.name = "count " & $i
          await stream.helloRequest(request)
          let reply = await stream.helloReply()
          if reply.has(message):
            echo reply.message

waitFor main()
