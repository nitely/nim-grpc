import std/strbasics
import std/uri

import pkg/hyperx/errors
import pkg/zippy

import ./protobuf
import ./errors
import ./statuscodes

func stackTrace2(err: ref Exception): string {.raises: [].} =
  doAssert err != nil
  result = ""
  result.add err.getStackTrace
  result.add "Error: "
  result.add err.msg
  result.add " ["
  result.add err.name
  result.add ']'

func fulltrace(err: ref Exception): string {.raises: [].} =
  doAssert err != nil
  result = ""
  var e = err
  while e != nil:
    result.add e.stackTrace2()
    if e.parent != nil:
      result.add "\nreraised from:\n"
    e = e.parent

func trace*(err: ref GrpcFailure): string {.raises: [].} =
  fulltrace err

func debugErr*(err: ref Exception) =
  when defined(grpcDebug) or defined(grpcDebugErr):
    debugEcho fulltrace(err)
  else:
    discard

template debugInfo*(s: untyped): untyped =
  when defined(grpcDebug):
    # hide "s" expresion side effcets
    {.cast(noSideEffect).}:
      debugEcho s
  else:
    discard

template catchHyperx*(body: untyped): untyped =
  try:
    body
  except HyperxError as err:
    debugErr err
    raise case err.typ
      of hyxLocalErr: newGrpcFailure(err.code.toGrpcStatusCode, parent = err)
      of hyxRemoteErr: newGrpcRemoteFailure(err.code.toGrpcStatusCode, parent = err)

template catch*(body: untyped): untyped =
  try:
    body
  except CatchableError as err:
    debugErr err
    raise newGrpcFailure(parent = err)

template check*(cond: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise newGrpcFailure()

template check*(cond, err: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise err

func newStringRef*(s: sink string = ""): ref string =
  new result
  result[] = s

func newSeqRef*[T](s: sink seq[T] = @[]): ref seq[T] =
  new result
  result[] = s

proc toWireData*(msg: string, compress = false): string {.raises: [GrpcFailure].} =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let compress = compress and msg.len > 860
  if compress:
    let msgc = catch compress(msg, BestSpeed, dfGzip)
    result = newString(msgc.len+5)
    for i in 0 .. msgc.len-1:
      result[i+5] = msgc[i]
  else:
    result = newString(msg.len+5)
    for i in 0 .. msg.len-1:
      result[i+5] = msg[i]
  let L = (result.len-5).uint
  result[0] = compress.char
  result[1] = ((L shr 24) and 8.ones).char
  result[2] = ((L shr 16) and 8.ones).char
  result[3] = ((L shr 8) and 8.ones).char
  result[4] = (L and 8.ones).char

proc fromWireData*(data: string): string {.raises: [GrpcFailure].} =
  doAssert data.len >= 5
  result = data[5 .. data.len-1]
  if data[0] == 1.char:
    result = catch uncompress(result)

proc pbEncode*[T](s: T, compress = false): ref string {.raises: [GrpcFailure].} =
  let ee = catch Protobuf.encode(s)
  var ss = newString(ee.len)
  for i in 0 .. ee.len-1:
    ss[i] = ee[i].char
  result = newStringRef ss.toWireData(compress)

proc pbDecode*[T](s: ref string, t: typedesc[T]): T {.raises: [GrpcFailure].} =
  let ss = s[].fromWireData
  result = catch Protobuf.decode(ss, t)

# XXX validate utf8; replace bad chars
func percentEnc*(s: string): string {.raises: [].} =
  ## rfc3986 percent encoder
  encodeUrl(s, usePlus = false)

func percentDec*(s: string): string {.raises: [].} =
  ## rfc3986 percent decoder
  decodeUrl(s, decodePlus = true)
