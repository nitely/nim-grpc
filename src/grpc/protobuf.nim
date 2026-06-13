import
  std/[macros, os, strformat],
  pkg/protobuf_serialization,
  pkg/protobuf_serialization/std/enums,
  pkg/protobuf_serialization/pkg/results,
  pkg/protobuf_serialization/files/type_generator

export protobuf_serialization, enums, results

proc serviceHook(packages: seq[ProtoNode]): NimNode =
  result = newStmtList()
  for p in packages:
    doAssert p.kind == ProtoType.Package
    for s in p.services:
      doAssert s.kind == ProtoType.Service
      for rpc in s.rpcs:
        doAssert rpc.kind == ProtoType.Rpc
        # p.packageName.replace('.', '_') &
        let rpcPathName = ident(&"{s.serviceName}{rpc.rpcName}Path")
        let rpcPathVal = if p.packageName != "":
          newStrLitNode(&"/{p.packageName}.{s.serviceName}/{rpc.rpcName}")
        else:
          newStrLitNode(&"/{s.serviceName}/{rpc.rpcName}")
        result.add quote do:
          const `rpcPathName`* = `rpcPathVal`

macro grpcProtoToTypes(filepath: static[string]): untyped =
  protoToTypesImpl(filepath, protoHook = serviceHook)

template importProto3*(file: static[string]): untyped =
  const filepath = parentDir(instantiationInfo(-1, true).filename) / file
  grpcProtoToTypes(filepath)
