import std/uri

import pkg/hyperx/errors
import pkg/zippy

import ./protobuf
import ./errors
import ./statuscodes

export protobuf

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

func grpcDebugErr*(err: ref Exception) =
  when defined(grpcDebug) or defined(grpcDebugErr):
    debugEcho fulltrace(err)
  else:
    discard

template grpcDebugInfo*(s: untyped): untyped =
  when defined(grpcDebug):
    # hide "s" expresion side effcets
    {.cast(noSideEffect).}:
      debugEcho s
  else:
    discard

template grpcCatchHyperx*(body: untyped): untyped =
  try:
    body
  except HyperxError as err:
    grpcDebugErr err
    raise case err.typ
      of hyxLocalErr: newGrpcFailure(err.code.toGrpcStatusCode, parent = err)
      of hyxRemoteErr: newGrpcRemoteFailure(err.code.toGrpcStatusCode, parent = err)

template grpcCatch*(body: untyped): untyped =
  try:
    body
  except CatchableError as err:
    grpcDebugErr err
    raise newGrpcFailure(parent = err)

template grpcCheck*(cond: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise newGrpcFailure()

template grpcCheck*(cond, err: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise err

func grpcNewStringRef*(s: sink string = ""): ref string =
  new result
  result[] = s

func grpcNewSeqRef*[T](s: sink seq[T] = @[]): ref seq[T] =
  new result
  result[] = s

template setLenUninit2*(s, newlen: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) >= (2, 2, 10):
    setLenUninit(s, newlen)
  else:
    setLen(s, newlen)

func add2*(s: var seq[byte], x: openArray[byte]) {.inline, raises: [].} =
  ## Faster than system's add, which copies byte by byte
  if x.len > 0:
    let L = s.len
    s.setLenUninit2(L+x.len)
    copyMem(addr s[L], addr x[0], x.len)

func toString*(s: openArray[byte]): string {.raises: [].} =
  ## Copy bytes into a string; for the public APIs that use strings
  result = newString(s.len)
  when nimvm:
    for i in 0 ..< s.len:
      result[i] = s[i].char
  else:
    if s.len > 0:
      copyMem(addr result[0], addr s[0], s.len)

proc grpcToWireData*(msg: seq[byte], compress = false): seq[byte] {.raises: [GrpcFailure].} =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let compress = compress and msg.len > 860
  result = newSeq[byte](5)
  if compress:
    result.add2 grpcCatch(zippy.compress(msg, BestSpeed, dfGzip))
  else:
    result.add2 msg
  let L = (result.len-5).uint
  result[0] = compress.byte
  result[1] = ((L shr 24) and 8.ones).byte
  result[2] = ((L shr 16) and 8.ones).byte
  result[3] = ((L shr 8) and 8.ones).byte
  result[4] = (L and 8.ones).byte

proc grpcFromWireData*(data: openArray[byte]): seq[byte] {.raises: [GrpcFailure].} =
  doAssert data.len >= 5
  result = @(toOpenArray(data, 5, data.len-1))
  if data[0] == 1:
    result = grpcCatch uncompress(result)

proc grpcPbEncode*[T](s: T, compress = false): ref seq[byte] {.raises: [GrpcFailure].} =
  let ee = grpcCatch Protobuf.encode(s)
  result = grpcNewSeqRef grpcToWireData(ee, compress)

proc grpcPbDecode*[T](s: ref seq[byte], t: typedesc[T]): T {.raises: [GrpcFailure].} =
  let ss = grpcFromWireData(s[])
  result = grpcCatch Protobuf.decode(ss, t)

# XXX validate utf8; replace bad chars
func grpcPercentEnc*(s: string): string {.raises: [].} =
  ## rfc3986 percent encoder
  encodeUrl(s, usePlus = false)

func grpcPercentDec*(s: string): string {.raises: [].} =
  ## rfc3986 percent decoder
  decodeUrl(s, decodePlus = true)
