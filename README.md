# gRpc

Pure Nim [gRPC](https://grpc.io) implementation.
It works on top of [hyperx](https://github.com/nitely/nim-hyperx).
Tested with go-grpc sever/client interop tests.

## Install

```
nimble install grpc
```

## Compatibility

> Nim +2.0

## Requirements

- OpenSSL

## Debugging

The `-d:grpcDebug` define will print debugging
messages and error traces

## ToDo

- [x] Client
- [x] Server
- [x] Compression
- [x] Interop tests
- [ ] Code gen proto Service
- [ ] JSON
- [ ] UDS
- [ ] non-TLS
- [ ] Auth

## LICENSE

MIT
