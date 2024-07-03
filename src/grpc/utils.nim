
import std/strbasics

import ./protobuf
import ./errors

template check*(cond: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    if not cond:
      raise newGrpcFailure()

func newStringRef*(s = ""): ref string =
  new result
  result[] = s

func newSeqRef*[T](s: seq[T] = @[]): ref seq[T] =
  new result
  result[] = s

func toWireData*(msg: string): string =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let L = msg.len.uint
  result = newStringOfCap(msg.len+5)
  result.setLen 5
  result[0] = 0.char  # uncompressed
  result[1] = ((L shr 24) and 8.ones).char
  result[2] = ((L shr 16) and 8.ones).char
  result[3] = ((L shr 8) and 8.ones).char
  result[4] = (L and 8.ones).char
  result.add msg

func fromWireData*(data: string): string =
  doAssert data.len >= 5
  doAssert data[0] == 0.char  # XXX uncompress
  result = newStringOfCap(data.len-5)
  result.add toOpenArray(data, 5, data.len-1)

proc pbEncode*[T](s: T): ref string =
  let ee = Protobuf.encode(s)
  var ss = newString(ee.len)
  for i in 0 .. ee.len-1:
    ss[i] = ee[i].char
  result = newStringRef(ss.toWireData)

proc pbDecode*[T](s: ref string, t: typedesc[T]): T =
  Protobuf.decode(s[].fromWireData, t)
