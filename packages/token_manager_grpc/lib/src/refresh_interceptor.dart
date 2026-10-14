import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';

import 'attempt_response_future.dart';
import 'attempt_response_stream.dart';
import 'call_attempts.dart';
import 'refresh_interceptor_delegate.dart';
import 'request_log.dart';

/// A gRPC client interceptor that sends calls with valid tokens and replays
/// a call once when the server rejects its tokens.
///
/// Unary calls go through [TokenManager.authorize] and streaming calls
/// through [TokenManager.authorizeStream]. A call fails with
/// `NotAuthenticated` when there are no tokens. A streaming call is made
/// again only before its first response, and only when its request stream
/// ended after at most one request. A rejected call that is not made again
/// reports its rejected tokens to the manager so a refresh can start for the
/// next call.
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
  ) {
    final attempts = CallAttempts();
    final log = RequestLog<Q>(requests);
    T? used;
    var reported = false;
    final responses = _manager.authorizeStream<R>(
      (tokens) => attempts.streaming(() {
        used = tokens;
        return invoker(method, log.next(), _withTokens(options, tokens));
      }),
      isAuthFailure: (error) {
        if (!_isAuthFailure(error)) return false;
        if (log.isReplayable) return true;
        // Report at most once per call; the call is not replayed.
        if (!reported) {
          reported = true;
          unawaited(_reportRejected(used));
        }
        return false;
      },
    );
    return AttemptResponseStream<R>(responses, attempts);
  }

  /// Asks the manager to renew [rejected] and ignores the outcome, because
  /// the call that used it fails with its own error.
  Future<void> _reportRejected(T? rejected) async {
    try {
      await _manager.validToken(rejected: rejected);
    } on Exception {
      // The caller already has the original error.
    }
  }

  bool _isAuthFailure(Object error) =>
      error is grpc.GrpcError && _delegate.shouldRefresh(error);

  grpc.CallOptions _withTokens(grpc.CallOptions options, T tokens) =>
      options.mergedWith(_delegate.buildCallOptions(tokens));
}
