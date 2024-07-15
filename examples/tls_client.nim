{.define: ssl.}

import std/asyncdispatch

import ../src/grpc/client
import ./pbtypes

proc main() {.async.} =
  #var client = newClient("127.0.0.1", Port 50051)
  var client = newClient("127.0.0.1", Port 4443)
  with client:
    block:
      echo "Simple request"
      let stream = client.newGrpcStream("/helloworld.Greeter/SayHello")
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        let reply = await stream.recvMessage(HelloReply)
        echo reply.message
    block:
      echo "Stream reply"
      let stream = client.newGrpcStream("/helloworld.Greeter/SayHelloStreamReply")
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        whileRecvMessages stream:
          let reply = await stream.recvMessage(HelloReply)
          echo reply.message
    block:
      echo "Bidirectional stream"
      let stream = client.newGrpcStream("/helloworld.Greeter/SayHelloBidiStream")
      with stream:
        for i in 0 .. 2:
          await stream.sendMessage(HelloRequest(name: "count " & $i))
          let reply = await stream.recvMessage(HelloReply)
          echo reply.message

waitFor main()
