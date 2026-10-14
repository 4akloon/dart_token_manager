import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

import 'bearer_delegate.dart';
import 'counting_refresher.dart';

/// A [TokenManager] holding the token `t0` and an interceptor over it.
final class GrpcFixture {
  /// Creates a fixture whose interceptor attaches tokens with [delegate];
  /// the session is signed out unless [signedIn].
  factory GrpcFixture({
    RefreshInterceptorDelegate<String> delegate = const BearerDelegate(),
    bool signedIn = true,
  }) {
    final refresher = CountingRefresher();
    final manager = TokenManager<String>.create(
      store: InMemoryTokenStore<String>(signedIn ? 't0' : null),
      refresher: refresher,
    );
    final interceptor = RefreshInterceptor<String>(
      manager: manager,
      delegate: delegate,
    );
    return GrpcFixture._(refresher, manager, interceptor);
  }

  GrpcFixture._(this.refresher, this.manager, this.interceptor);

  /// The method every test calls.
  static final grpc.ClientMethod<String, String> method =
      grpc.ClientMethod<String, String>(
        '/test.Echo/Call',
        utf8.encode,
        utf8.decode,
      );

  /// The refresher behind [manager]; its n-th refresh returns `tn`.
  final CountingRefresher refresher;

  /// The manager the interceptor takes tokens from.
  final TokenManager<String> manager;

  /// The interceptor under test.
  final RefreshInterceptor<String> interceptor;

  /// Lets every pending microtask and zero-delay timer run.
  static Future<void> settle() => Future<void>.delayed(Duration.zero);
}
