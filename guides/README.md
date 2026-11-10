# native_desktop Guides

`native_desktop` is a host-neutral native-controls library. It expects an existing GUI host to own application startup, the event loop, and native windows. The shard owns platform selection, FFI, native resources, and cross-platform models behind its public API.

Use these guides alongside the API examples in the project [README](../README.md):

- [Host integration](host-integration.md) explains GUI-thread attachment, background execution, Windows message forwarding, native window handles, and shutdown ordering.
- [Platform support](platform-support.md) lists the supported services and the platform constraints that applications need to handle.
- [Resource lifecycle](resource-lifecycle.md) describes ownership, cleanup, callbacks, concurrency, and rules for host-owned handles.

Generated API documentation is available through `crystal docs`.

## Framework adapters

This documentation describes `native_desktop` itself and does not assume a particular application framework. A framework adapter may add security policy, IPC commands, serialization, lifecycle hooks, or frontend-facing models, but those concerns are outside the shard’s API contract.
