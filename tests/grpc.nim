{.define: ssl.}

import std/tables

import ../src/grpc/protobuf

importProto3("test.proto")

let x = EchoStatus(message: "foo", code: 1)
let encoded = Protobuf.encode(x)
echo $encoded
