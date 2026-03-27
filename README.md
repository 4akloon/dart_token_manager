## Dart Token Manager

Monorepo with `token_manager` packages for centralized token lifecycle handling.

## Packages

- `packages/token_manager` - core token lifecycle API (storage, refresh, stream).
- `packages/token_manager_dio` - Dio interceptor for automatic refresh and retry.
- `packages/token_manager_grpc` - gRPC client interceptor for auth refresh and retry.

Per-package docs:

- Core: [packages/token_manager/README.md](packages/token_manager/README.md)
- Dio: [packages/token_manager_dio/README.md](packages/token_manager_dio/README.md)
- gRPC: [packages/token_manager_grpc/README.md](packages/token_manager_grpc/README.md)

## Quick start

```yaml
dependencies:
  token_manager: ^0.1.0
  token_manager_dio: ^0.1.0
  token_manager_grpc: ^0.1.0
```
