import std/strutils
import ./types

iterator headersIt(s: string): (Slice[int], Slice[int]) {.inline.} =
  let L = s.len
  var na = 0
  var nb = 0
  var va = 0
  var vb = 0
  while na < L:
    nb = na
    nb += int(s[na] == ':')  # pseudo-header
    nb = find(s, ':', nb)
    doAssert nb != -1
    assert s[nb] == ':'
    assert s[nb+1] == ' '
    va = nb+2  # skip :\s
    vb = find(s, '\r', va)
    doAssert vb != -1
    assert s[vb] == '\r'
    assert s[vb+1] == '\n'
    yield (na .. nb-1, va .. vb-1)
    doAssert vb+2 > na
    na = vb+2  # skip /r/n

func parseStatusCode(raw: openArray[char]): StatusCode =
  if raw.len notin 1 .. 2:
    return stcUnknown
  for x in raw:
    if x.ord notin '0'.ord .. '9'.ord:
      return stcUnknown
  var code = raw[0].ord - '0'.ord
  if raw.len > 1:
    code = code * 10 + (raw[1].ord - '0'.ord)
  if code > 16:
    return stcUnknown
  return code.StatusCode

type ResponseHeaders* = ref object
  status*: StatusCode
  statusMsg*: string

func newResponseHeaders(status: StatusCode): ResponseHeaders =
  ResponseHeaders(
    status: status,
    statusMsg: ""
  )

func toResponseHeaders*(s: string): ResponseHeaders =
  result = newResponseHeaders(stcUnknown)
  for (nn, vv) in headersIt s:
    if toOpenArray(s, nn.a, nn.b) == "grpc-status":
      result.status = parseStatusCode toOpenArray(s, vv.a, vv.b)
    elif toOpenArray(s, nn.a, nn.b) == "grpc-message":
      result.statusMsg = s[vv]
