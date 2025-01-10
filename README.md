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

- The protobuf library [does not support enums](https://github.com/status-im/nim-protobuf-serialization/issues/39). You may change enums to int32 and they will work fine for interop.

## LICENSE

MIT
