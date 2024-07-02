{.define: ssl.}

import std/asyncdispatch

import ../src/grpc/client
import ../src/grpc/utils
import ../src/grpc/protobuf

importProto3("hello.proto")

proc sayHello(
  client: ClientContext, request: HelloRequest
): Future[HelloReply] {.async.} =
  let data = await client.get(
    newStringRef("/helloworld.Greeter/SayHello"),
    request.pbEncode()
  )
  result = data.pbDecode(HelloReply)

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
    request.pbEncode(), finish
  )

proc helloReply(strm: GrpcStream): Future[HelloReply] {.async.} =
  let data = newStringRef()
  await strm.recvBody(data)
  result = data.pbDecode(HelloReply)

proc main() {.async.} =
  #var client = newClient("127.0.0.1", Port 50051)
  var client = newClient("127.0.0.1", Port 4443)
  with client:
    block:
      echo "Simple request"
      let request = HelloRequest(name: "you")
      let reply = await client.sayHello(request)
      echo reply.message
    when false:
      echo "Stream reply"
      let stream = client.sayHelloStreamReply()
      with stream:
        let request = HelloRequest(name: "you")
        await stream.helloRequest(request, finish = true)
        while not stream.recvEnded:
          let reply = await stream.helloReply()
          echo reply.message
    when false:
      echo "Bidirectional stream"
      let stream = client.sayHelloBidiStream()
      with stream:
        for i in 0 .. 2:
          let request = HelloRequest(name: "count " & $i)
          await stream.helloRequest(request)
          let reply = await stream.helloReply()
          echo reply.message

waitFor main()
