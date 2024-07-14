import std/strutils
import ./statuscodes
import ./utils
import ./errors

iterator headersIt*(s: string): (Slice[int], Slice[int]) {.inline.} =
  ## Ported from hyperx
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
      result.statusMsg = percentDec s[vv]

func toMillis(tt: int, unit: char): int {.raises: [GrpcFailure].} =
  case unit
  of 'H':
    check tt < int.high div 3600000, newGrpcFailure()
    tt * 3600000
  of 'M':
    check tt < int.high div 60000, newGrpcFailure()
    tt * 60000
  of 'S':
    check tt < int.high div 1000, newGrpcFailure()
    tt * 1000
  of 's':
    tt
  of 'u':
    if tt <= 1000: 1 else: tt div 1000
  of 'n':
    if tt <= 1_000_000: 1 else: tt div 1_000_000
  else:
    doAssert false; 0

func parseTimeout(raw: openArray[char]): int {.raises: [GrpcFailure].} =
  check raw.len in 3 .. 10, newGrpcFailure()
  check raw[^1] in {'H', 'M', 'S', 's', 'u', 'n'}, newGrpcFailure()
  check raw[^2] == ' ', newGrpcFailure()
  var timeout = 0
  for i in 0 .. raw.len-3:
    if raw[i].ord in '0'.ord .. '9'.ord:
      timeout = timeout * 10 + (raw[i].ord - '0'.ord)
    else:
      raise newGrpcFailure()
  return toMillis(timeout, raw[^1])

type RequestHeaders* = ref object
  path*: string
  timeout*: int

func newRequestHeaders(): RequestHeaders =
  RequestHeaders(path: "", timeout: 0)

func toRequestHeaders*(s: string): RequestHeaders {.raises: [GrpcFailure].} =
  result = newRequestHeaders()
  for (nn, vv) in headersIt s:
    if toOpenArray(s, nn.a, nn.b) == ":path":
      result.path = s[vv.a .. vv.b]
    elif toOpenArray(s, nn.a, nn.b) == "grpc-timeout":
      result.timeout = parseTimeout toOpenArray(s, vv.a, vv.b)
