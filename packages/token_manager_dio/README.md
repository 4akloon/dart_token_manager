## token_manager_dio

[![Pub Version](https://img.shields.io/pub/v/token_manager_dio.svg)](https://pub.dev/packages/token_manager_dio)

`token_manager_dio` provides a Dio interceptor that:

- injects auth tokens into outgoing requests;
- waits for active refresh before requests;
- retries failed calls after token refresh.

## Installation

```yaml
dependencies:
  token_manager: ^0.1.0
  token_manager_dio: ^0.1.0
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class AppTokens {
  const AppTokens(this.accessToken);
  final String accessToken;
}

final class DioAuthDelegate extends RefreshInterceptorDelegate<AppTokens> {
  @override
  void applyTokensToRequest(RequestOptions options, AppTokens? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

Future<void> configureClient(
  Dio dio,
  TokenManager<AppTokens> manager,
) async {
  dio.interceptors.add(
    RefreshInterceptor<AppTokens>(
      manager: manager,
      delegate: DioAuthDelegate(),
    ),
  );
}
```

For a complete runnable example, see `example/main.dart`.
