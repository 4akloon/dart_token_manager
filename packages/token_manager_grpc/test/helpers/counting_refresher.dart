import 'dart:async';

import 'package:token_manager/token_manager.dart';

/// A refresher whose n-th refresh returns the token `tn`.
final class CountingRefresher implements TokenRefresher<String> {
  /// How many refreshes started.
  int calls = 0;

  /// The token each refresh was asked to replace, in order.
  final List<String> replaced = [];

  /// When set, every refresh waits for it before it returns.
  Completer<void>? gate;

  @override
  Future<String> refresh(String current) async {
    calls++;
    replaced.add(current);
    final token = 't$calls';
    await gate?.future;
    return token;
  }
}
