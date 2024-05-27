import std/asyncdispatch

import pkg/hyperx/client

import ./errors
import ./headers
import ./types

export
  ClientContext,
  newClient,
  withClient,
  GrpcResponseError

func newSeqRef[T](s: seq[T]): ref seq[T] =
  result = new(seq[T])
  result[] = s

func newStringRef(s = ""): ref string =
  new result
  result[] = s

proc recv(
  strm: ClientStream,
  headers, data: ref string
) {.async.} =
  await strm.recvHeaders(headers)
  while not strm.recvEnded:
    await strm.recvBody(data)

proc send(
  strm: ClientStream,
  path: ref string,
  data: ref string
) {.async.} =
  await strm.sendHeaders(
    newSeqRef(@[
      (":method", "POST"),
      (":scheme", "https"),
      (":path", path[]),
      (":authority", strm.client.hostname),
      ("te", "trailers"),
      ("grpc-encoding", "identity"),
      ("grpc-accept-encoding", "identity"),
      ("user-agent", "grpc-nim/0.1.0"),
      ("content-type", "application/grpc+proto"),
      ("content-length", $data[].len)
    ]),
    finish = false
  )
  await strm.sendBody(data, finish = true)

proc get*(
  client: ClientContext,
  path: ref string,
  data: ref string
): Future[ref string] {.async.} =
  let strm = client.newClientStream()
  withStream strm:
    # start recv before send in case of error
    result = newStringRef()
    let headersIn = newStringRef()
    let recvFut = strm.recv(headersIn, result)
    let sendFut = strm.send(path, data)
    var connErr: ref HyperxConnError = nil
    var strmErr: ref HyperxStrmError = nil
    try:
      await sendFut
    except HyperxStrmError as err:
      debugEcho err.msg
      strmErr = err
    except HyperxConnError as err:
      debugEcho err.msg
      connErr = err
    try:
      await recvFut
    except HyperxStrmError as err:
      debugEcho err.msg
      strmErr = err
    except HyperxConnError as err:
      debugEcho err.msg
      connErr = err
    #echo headersIn[]
    let respHeaders = toResponseHeaders headersIn[]
    if respHeaders.status != stcOk:
      raise newGrpcResponseError(
        respHeaders.statusMsg,
        respHeaders.status
      )
    if connErr != nil:
      raise (ref HyperxConnError)(msg: connErr.msg)
    if strmErr != nil:
      raise (ref HyperxStrmError)(msg: strmErr.msg)
