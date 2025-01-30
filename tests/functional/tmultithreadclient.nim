import std/asyncdispatch

import ../../src/grpc
import ./pbtypes

const strmsPerClient = 61
const clientsCount = 61

var checked {.threadvar.}: int
var id {.threadvar.}: int

proc sayHello(client: ClientContext) {.async.} =
  id += 1
  let sid = $id
  let stream = client.newGrpcStream(GreeterSayHelloPath)
  with stream:
    await stream.sendMessage(HelloRequest(name: "you" & sid))
    let reply = await stream.recvMessage(HelloReply)
    doAssert reply.message == "Hello, you" & sid
    checked += 1

proc spawnClient {.async.} =
  var reqs = newSeq[Future[void]]()
  var client = newClient("127.0.0.1", Port 8121, ssl = false)
  with client:
    for _ in 0 .. strmsPerClient-1:
      reqs.add client.sayHello()
    for req in reqs:
      await req

proc main {.async.} =
  var clients = newSeq[Future[void]]()
  for _ in 0 .. clientsCount-1:
    clients.add spawnClient()
  for c in clients:
    await c

proc worker(result: ptr int) {.thread.} =
  waitFor main()
  doAssert not hasPendingOperations()
  setGlobalDispatcher(nil)
  #destroyClientSslContext()
  result[] = checked

proc run =
  var threads = newSeq[Thread[ptr int]](8)
  var results = newSeq[int](threads.len)
  for i in 0 .. threads.len-1:
    createThread(threads[i], worker, addr results[i])
  for i in 0 .. threads.len-1:
    joinThread(threads[i])
  for checked in results:
    doAssert checked == clientsCount * strmsPerClient
    echo "checked ", $checked

(proc =
  run()
  echo "ok"
)()
