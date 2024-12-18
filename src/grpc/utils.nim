import std/strbasics
import std/uri

import pkg/hyperx/errors
import pkg/zippy

import ./protobuf
import ./errors
import ./statuscodes

template debugInfo*(s: untyped): untyped =
  when defined(grpcDebug):
    # hide "s" expresion side effcets
    {.cast(noSideEffect).}:
      debugEcho s
  else:
    discard

template tryHyperx*(body: untyped): untyped =
  try:
    body
  except HyperxError as err:
    debugInfo err.getStackTrace()
    debugInfo err.msg
    raise case err.typ
      of hyxLocalErr: newGrpcFailure(err.code.toGrpcStatusCode)
      of hyxRemoteErr: newGrpcRemoteFailure(err.code.toGrpcStatusCode)

template tryCatch*(body: untyped): untyped =
  try:
    body
  except CatchableError:
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg
    raise newGrpcFailure()

template check*(cond: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise newGrpcFailure()

template check*(cond, err: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise err

func newStringRef*(s = ""): ref string =
  new result
  result[] = s

func newSeqRef*[T](s: seq[T] = @[]): ref seq[T] =
  new result
  result[] = s

proc toWireData*(msg: string, compress = false): string {.raises: [GrpcFailure].} =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let msg = if compress:
    tryCatch compress(msg, BestSpeed, dfGzip)
  else:
    msg
  let L = msg.len.uint
  result = newStringOfCap(msg.len+5)
  result.setLen 5
  result[0] = compress.char
  result[1] = ((L shr 24) and 8.ones).char
  result[2] = ((L shr 16) and 8.ones).char
  result[3] = ((L shr 8) and 8.ones).char
  result[4] = (L and 8.ones).char
  result.add msg

proc fromWireData*(data: string): string {.raises: [GrpcFailure].} =
  doAssert data.len >= 5
  result = newStringOfCap(data.len-5)
  result.add toOpenArray(data, 5, data.len-1)
  if data[0] == 1.char:
    result = tryCatch uncompress(result)

proc pbEncode*[T](s: T, compress = false): ref string {.raises: [GrpcFailure].} =
  let ee = tryCatch Protobuf.encode(s)
  var ss = newString(ee.len)
  for i in 0 .. ee.len-1:
    ss[i] = ee[i].char
  result = newStringRef ss.toWireData(compress)

proc pbDecode*[T](s: ref string, t: typedesc[T]): T {.raises: [GrpcFailure].} =
  let ss = s[].fromWireData
  result = tryCatch Protobuf.decode(ss, t)

# XXX validate utf8; replace bad chars
func percentEnc*(s: string): string {.raises: [].} =
  ## rfc3986 percent encoder
  encodeUrl(s, usePlus = false)

func percentDec*(s: string): string {.raises: [].} =
  ## rfc3986 percent decoder
  decodeUrl(s, decodePlus = true)
