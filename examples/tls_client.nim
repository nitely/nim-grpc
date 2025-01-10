{.define: ssl.}

import std/asyncdispatch

import ../src/grpc
import ./pbtypes

proc main() {.async.} =
  #var client = newClient("127.0.0.1", Port 50051)
  var client = newClient("127.0.0.1", Port 8113)
  with client:
    block:
      echo "Simple request"
      let stream = client.newGrpcStream(GreeterSayHelloPath)
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        let reply = await stream.recvMessage(HelloReply)
        doAssert reply.message == "Hello, you"
    block:
      echo "Stream reply"
      let stream = client.newGrpcStream(GreeterSayHelloStreamReplyPath)
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        var i = 0
        whileRecvMessages stream:
          let reply = await stream.recvMessage(HelloReply)
          doAssert reply.message == "Hello, you " & $i
          inc i
        doAssert i == 3
    block:
      echo "Bidirectional stream"
      let stream = client.newGrpcStream(GreeterSayHelloBidiStreamPath)
      with stream:
        for i in 0 .. 2:
          await stream.sendMessage(HelloRequest(name: "count " & $i))
          let reply = await stream.recvMessage(HelloReply)
          doAssert reply.message == "Hello, count " & $i

waitFor main()
