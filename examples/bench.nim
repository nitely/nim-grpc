import std/asyncdispatch

import pkg/hyperx/limiter
#import pkg/hyperx/clientserver

import ../src/grpc
import ./pbtypes

proc sayHello(client: ClientContext) {.async.} =
  let stream = client.newGrpcStream(GreeterSayHelloPath)
  with stream:
    await stream.sendMessage(HelloRequest(name: "you"), finish = true)
    let reply = await stream.recvMessage(HelloReply)
    doAssert reply.message == "Hello, you"

proc doWork {.async.} =
  let client = newClient("127.0.0.1", Port 8115, ssl = false)
  with client:
    let lt = newLimiter(100)
    for _ in 0 .. 10_000:
      await lt.spawn client.sayHello()
    await lt.join()
    #echoStats client

proc main {.async.} =
  let lt = newLimiter(100_000)
  for _ in 0 ..< 10:
    await lt.spawn doWork()
  await lt.join()
  echo "ok"

waitFor main()
