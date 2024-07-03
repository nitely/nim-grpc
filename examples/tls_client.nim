{.define: ssl.}

import std/asyncdispatch

import ../src/grpc/client
import ../src/grpc/utils

importProto3("hello.proto")

proc sayHello(client: ClientContext): GrpcStream =
  client.newGrpcStream(
    "/helloworld.Greeter/SayHello"
  )

proc sayHelloStreamReply(client: ClientContext): GrpcStream =
  client.newGrpcStream(
    "/helloworld.Greeter/SayHelloStreamReply"
  )

proc sayHelloBidiStream(client: ClientContext): GrpcStream =
  client.newGrpcStream(
    "/helloworld.Greeter/SayHelloBidiStream"
  )

proc main() {.async.} =
  #var client = newClient("127.0.0.1", Port 50051)
  var client = newClient("127.0.0.1", Port 4443)
  with client:
    block:
      echo "Simple request"
      let stream = client.sayHello()
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        let reply = await stream.recvMessage(HelloReply)
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
