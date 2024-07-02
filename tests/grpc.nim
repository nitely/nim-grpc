{.define: ssl.}

import std/tables
import pkg/protobuf_serialization
import pkg/protobuf_serialization/proto_parser

import_proto3("test.proto")

let x = EchoStatus(message: "foo", code: 1)
let encoded = Protobuf.encode(x)
echo $encoded
