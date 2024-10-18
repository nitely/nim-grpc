{.define: ssl.}

import std/asyncdispatch

import ../src/grpc
import ./pbtypes

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

testAsync "simple_request":
  var checked = 0
  var client = newClient("127.0.0.1", Port 8114)
  with client:
    let stream = client.newGrpcStream("/helloworld.Greeter/TestHello")
    with stream:
      await stream.sendMessage(HelloRequest(name: "you"))
      let reply = await stream.recvMessage(HelloReply)
      doAssert reply.message == "Hello, you"
      inc checked
  doAssert checked == 1

testAsync "error_propagation":
  var checked = 0
  var client = newClient("127.0.0.1", Port 8114)
  try:
    with client:
      let stream = client.newGrpcStream("/helloworld.Greeter/TestHello")
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        raise newException(ValueError, "test foo")
  except ValueError as err:
    doAssert err.msg == "test foo"
    inc checked
  doAssert checked == 1
