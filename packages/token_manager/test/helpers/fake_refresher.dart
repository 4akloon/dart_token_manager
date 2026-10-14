import 'dart:async';

import 'package:token_manager/src/token_refresher.dart';

/// A refresher whose calls stay pending until a test completes or fails them.
final class FakeRefresher<T> implements TokenRefresher<T> {
  /// The tokens each call was asked to refresh, in call order.
  final List<T> requested = [];

  final List<Completer<T>> _calls = [];

  /// How many times [refresh] was called.
  int get callCount => _calls.length;

  @override
  Future<T> refresh(T current) {
    requested.add(current);
    final call = Completer<T>();
    _calls.add(call);
    return call.future;
  }

  /// Completes call number [call] with [tokens].
  void complete(T tokens, {int call = 0}) => _calls[call].complete(tokens);

  /// Fails call number [call] with [error].
  void fail(Object error, {int call = 0}) => _calls[call].completeError(error);
}
