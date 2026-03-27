## token_manager_grpc

[![Pub Version](https://img.shields.io/pub/v/token_manager_grpc.svg)](https://pub.dev/packages/token_manager_grpc)

`token_manager_grpc` provides a gRPC client interceptor that:

- builds auth call metadata from current tokens;
- waits for in-flight refresh before requests;
- retries unary and stream calls on `UNAUTHENTICATED`.

## Installation

```yaml
dependencies:
  token_manager: ^0.1.0
  token_manager_grpc: ^0.1.0
```

## Usage

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class AppTokens {
  const AppTokens(this.accessToken);
  final String accessToken;
}

final class GrpcAuthDelegate extends RefreshInterceptorDelegate<AppTokens> {
  @override
  grpc.CallOptions buildCallOptions(AppTokens? tokens) {
    final metadata = <String, String>{};
    if (tokens != null) {
      metadata['authorization'] = 'Bearer ${tokens.accessToken}';
    }
    return grpc.CallOptions(metadata: metadata);
  }
}

RefreshInterceptor<AppTokens> createInterceptor(TokenManager<AppTokens> manager) {
  return RefreshInterceptor<AppTokens>(
    manager: manager,
    delegate: GrpcAuthDelegate(),
  );
}
```

For a complete runnable example, see `example/main.dart`.
