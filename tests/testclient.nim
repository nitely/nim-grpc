{.define: ssl.}

import std/asyncdispatch

import ../src/grpc
import ../src/grpc/statuscodes
import ./pbtypes
from ../src/grpc/clientserver import testBuffAll

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

const localHost = "127.0.0.1"
const localPort = Port 8114
const testHelloPath = GreeterTestHelloPath
const testHelloUniPath = GreeterTestHelloUniPath
const testHelloBidiPath = GreeterTestHelloBidiPath

testAsync "simple_request":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloPath)
    with stream:
      await stream.sendMessage(HelloRequest(name: "you"))
      let reply = await stream.recvMessage(HelloReply)
      doAssert reply.message == "Hello, you"
      inc checked
  doAssert checked == 1

testAsync "simple_request_2":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    for i in 0 .. 2:
      let stream = client.newGrpcStream(testHelloPath)
      with stream:
        await stream.sendMessage(HelloRequest(name: "you" & $i))
        let reply = await stream.recvMessage(HelloReply)
        doAssert reply.message == "Hello, you" & $i
        inc checked
  doAssert checked == 3

testAsync "error_propagation":
  var checked = 0
  var client = newClient(localHost, localPort)
  try:
    with client:
      let stream = client.newGrpcStream(testHelloPath)
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        raise newException(ValueError, "test foo")
  except ValueError as err:
    doAssert err.msg == "test foo"
    inc checked
  doAssert checked == 1

testAsync "error_propagation_2":
  var checked = 0
  var client = newClient(localHost, localPort)
  try:
    with client:
      let stream = client.newGrpcStream(testHelloPath)
      with stream:
        raise newException(ValueError, "test foo")
  except ValueError as err:
    doAssert err.msg == "test foo"
    inc checked
  doAssert checked == 1

testAsync "error_propagation_3":
  var checked = 0
  var client = newClient(localHost, localPort)
  try:
    with client:
      let stream = client.newGrpcStream(testHelloPath)
      with stream:
        await stream.sendMessage(HelloRequest(name: "you"))
        discard await stream.recvMessage(HelloReply)
        raise newException(ValueError, "test foo")
  except ValueError as err:
    doAssert err.msg == "test foo"
    inc checked
  doAssert checked == 1

testAsync "big_payload":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloPath)
    with stream:
      var payload = ""
      for i in 0 .. 123_123:
        payload.add "abcdefg"[i mod 7]
      await stream.sendMessage(HelloRequest(name: payload))
      let reply = await stream.recvMessage(HelloReply)
      doAssert reply.message == "Hello, " & payload
      inc checked
  doAssert checked == 1

testAsync "big_payload_stream":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloBidiPath)
    with stream:
      var payload = ""
      for i in 0 .. 123_123:
        payload.add "abcdefg"[i mod 7]
      for i in 0 .. 2:
        await stream.sendMessage(HelloRequest(name: payload & $i))
        let reply = await stream.recvMessage(HelloReply)
        doAssert reply.message == "Hello, " & payload & $i
        inc checked
  doAssert checked == 3

testAsync "deadline":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloPath, timeout = 1)
    try:
      with stream:
        #await stream.sendMessage(HelloRequest(name: "you"))
        discard await stream.recvMessage(HelloReply)
        doAssert false
    except GrpcFailure as err:
      doAssert err.code == grpcDeadlineEx, $err.code
      inc checked
  doAssert checked == 1

testAsync "deadline_not_reached":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloPath, timeout = 1, timeoutUnit = grpcHour)
    with stream:
      await stream.sendMessage(HelloRequest(name: "you"))
      let reply = await stream.recvMessage(HelloReply)
      doAssert reply.message == "Hello, you"
      inc checked
  doAssert checked == 1
  # wait for deadline to expire
  while hasPendingOperations():
    await sleepAsync(1)

testAsync "stream_response":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloUniPath)
    with stream:
      await stream.sendMessage(HelloRequest(name: "you"))
      var i = 0
      whileRecvMessages stream:
        let reply = await stream.recvMessage(HelloReply)
        doAssert reply.message == "Hello, you " & $i
        inc i
      doAssert i == 10
      inc checked
  doAssert checked == 1

testAsync "stream_response_backlog":
  var checked = 0
  var client = newClient(localHost, localPort)
  with client:
    let stream = client.newGrpcStream(testHelloUniPath)
    with stream:
      await stream.sendMessage(HelloRequest(name: "you"))
      await stream.testBuffAll()
      var i = 0
      whileRecvMessages stream:
        let reply = await stream.recvMessage(HelloReply)
        doAssert reply.message == "Hello, you " & $i
        inc i
      doAssert i == 10
      inc checked
  doAssert checked == 1
