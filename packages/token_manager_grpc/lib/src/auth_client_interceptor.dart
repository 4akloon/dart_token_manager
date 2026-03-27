import 'dart:async';

import 'package:token_manager/token_manager.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'async_response_future.dart';
import 'async_response_stream.dart';
import 'refresh_interceptor_delegate.dart';

class RefreshInterceptor<T> implements grpc.ClientInterceptor {
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
  ) => AsyncResponseFuture.fromCallback((setResponse) async {
    await _manager.waitForFresh;
    final tokens = _manager.tokens;

    if (tokens == null) {
      return invoker(method, request, options);
    }

    final responseFuture = invoker(
      method,
      request,
      options.mergedWith(_buildAuthOptions(tokens)),
    );

    setResponse(responseFuture);

    try {
      await responseFuture;
      return responseFuture;
    } catch (error) {
      if (error case grpc.GrpcError(code: grpc.StatusCode.unauthenticated)) {
        await _manager.executeRefresh();

        final refreshedTokens = _manager.tokens;

        if (refreshedTokens == null) {
          return invoker(method, request, options);
        }

        final newResponseFuture = invoker(
          method,
          request,
          options.mergedWith(_buildAuthOptions(refreshedTokens)),
        );

        setResponse(newResponseFuture);
        return newResponseFuture;
      } else {
        rethrow;
      }
    }
  });

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

  grpc.CallOptions? _buildAuthOptions(T tokens) =>
      _delegate.buildCallOptions(tokens);
}
