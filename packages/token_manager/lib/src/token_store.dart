import 'package:rxdart/rxdart.dart';

import 'token_storage.dart';

class TokenStore<T> {
  TokenStore({required TokenStorage<T> storage})
    : _storage = storage,
      _tokensSubject = BehaviorSubject.seeded(null);

  final TokenStorage<T> _storage;
  final BehaviorSubject<T?> _tokensSubject;

  T? get tokens => _tokensSubject.value;

  Stream<T?> get tokensStream => _tokensSubject.stream;

  Future<void> initialize() async {
    final initialTokens = await _storage.getTokens();

    await setTokens(initialTokens);
  }

  Future<void> setTokens(T? tokens) async {
    if (_tokensSubject.isClosed) return;

    _tokensSubject.add(tokens);

    await _storage.setTokens(tokens);
  }

  Future<void> dispose() => _tokensSubject.close();
}
