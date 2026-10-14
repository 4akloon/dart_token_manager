// interceptStreaming still uses the deprecated token_manager API until Task 6.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';

import 'async_response_stream.dart';
import 'attempt_response_future.dart';
import 'call_attempts.dart';
import 'refresh_interceptor_delegate.dart';

/// A gRPC client interceptor that sends calls with valid tokens and replays
/// a call once when the server rejects its tokens.
class RefreshInterceptor<T> implements grpc.ClientInterceptor {
  /// Creates an interceptor that takes tokens from [manager] and attaches
  /// them with [delegate].
  const RefreshInterceptor({
    required TokenManager<T> manager,
    required RefreshInterceptorDelegate<T> delegate,
  }) : _manager = manager,
       _delegate = delegate;

  final TokenManager<T> _manager;
  final RefreshInterceptorDelegate<T> _delegate;

  @override
  grpc.ResponseFuture<R> interceptUnary<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
    grpc.ClientUnaryInvoker<Q, R> invoker,
  ) {
    final attempts = CallAttempts();
    final response = _manager.authorize<R>(
      (tokens) => attempts.unary(
        () => invoker(method, request, _withTokens(options, tokens)),
      ),
      isAuthFailure: _isAuthFailure,
    );
    return AttemptResponseFuture<R>(response, attempts);
  }

  @override
  grpc.ResponseStream<R> interceptStreaming<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
    grpc.ClientStreamingInvoker<Q, R> invoker,
  ) => AsyncResponseStream.fromCallback((controller, setStream) async {
    await _manager.waitForFresh;
    final tokens = _manager.tokens;

    Future<void> forward(grpc.ResponseStream<R> stream) async {
      setStream(stream);
      await for (final item in stream) {
        controller.add(item);
      }
    }

    if (tokens == null) {
      await forward(invoker(method, requests, options));
      return;
    }

    try {
      await forward(
        invoker(
          method,
          requests,
          options.mergedWith(_buildAuthOptions(tokens)),
        ),
      );
    } catch (error) {
      if (error case grpc.GrpcError(code: grpc.StatusCode.unauthenticated)) {
        await _manager.executeRefresh();

        final refreshedTokens = _manager.tokens;

        if (refreshedTokens == null) {
          await forward(invoker(method, requests, options));
          return;
        }

        await forward(
          invoker(
            method,
            requests,
            options.mergedWith(_buildAuthOptions(refreshedTokens)),
          ),
        );
      } else {
        rethrow;
      }
    }
  });

  bool _isAuthFailure(Object error) =>
      error is grpc.GrpcError && _delegate.shouldRefresh(error);

  grpc.CallOptions _withTokens(grpc.CallOptions options, T tokens) =>
      options.mergedWith(_delegate.buildCallOptions(tokens));

  grpc.CallOptions? _buildAuthOptions(T tokens) =>
      _delegate.buildCallOptions(tokens);
}
