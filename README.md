## Dart Token Manager

Monorepo with `token_manager` packages for centralized token lifecycle handling.

## Packages

- `packages/token_manager` - core token lifecycle API (storage, refresh, stream).
- `packages/token_manager_dio` - `DioTokenInterceptor` for Dio: attaches the token and replays once after an auth failure.
- `packages/token_manager_grpc` - `GrpcTokenInterceptor` for gRPC clients: attaches the token and replays once after an auth failure.
- `packages/token_manager_gql` - `gql_link` `Link` that attaches the token and replays once after an auth failure.

Per-package docs:

- Core: [packages/token_manager/README.md](packages/token_manager/README.md)
- Dio: [packages/token_manager_dio/README.md](packages/token_manager_dio/README.md)
- gRPC: [packages/token_manager_grpc/README.md](packages/token_manager_grpc/README.md)
- GraphQL: [packages/token_manager_gql/README.md](packages/token_manager_gql/README.md)

## Quick start

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0
  token_manager_grpc: ^0.2.0
  token_manager_gql: ^0.1.0
```
