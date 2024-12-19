# gRpc

Pure Nim [gRPC](https://grpc.io) implementation.
It works on top of [hyperx](https://github.com/nitely/nim-hyperx).
Tested with go-grpc server/client interop tests.

## Install

```
nimble install grpc
```

## Compatibility

> Nim +2.0

## Requirements

- OpenSSL

# Usage

Read the examples and the interop tests.

## Debugging

The `-d:grpcDebug` define will print debugging
messages and error traces

## Limitations

- Service code generation is missing. As seen in the [tls_server example](https://github.com/nitely/nim-grpc/blob/master/examples/tls_server.nim) this is not terrible, but services and messages must be kept in separate files, since the protobuf library can only parse messages.
- The protobuf library [does not support enums](https://github.com/status-im/nim-protobuf-serialization/issues/39). You may change enums to int32 and they will work fine.

## LICENSE

MIT
