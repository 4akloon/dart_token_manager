import 'dart:async';

import 'package:token_manager/src/token_store.dart';

/// A store that counts calls, records their order and can be made to fail.
final class FakeTokenStore<T> implements TokenStore<T> {
  /// Creates a store holding [stored].
  FakeTokenStore([this.stored]);

  /// The tokens currently stored.
  T? stored;

  /// How many times [read] was called.
  int reads = 0;

  /// How many times [write] was called.
  int writes = 0;

  /// How many times [delete] was called.
  int deletes = 0;

  /// When set, [read] throws it.
  Exception? readError;

  /// When set, [read] returns the stored value only after it completes; the
  /// value is captured before the wait.
  Completer<void>? readGate;

  /// When set, [write] throws it.
  Exception? writeError;

  /// When set, [delete] throws it.
  Exception? deleteError;

  /// The successful mutations in order: `write` or `delete`.
  final List<String> log = [];

  @override
  Future<T?> read() async {
    reads++;
    final error = readError;
    final snapshot = stored;
    await readGate?.future;
    if (error != null) {
      throw error;
    }
    return snapshot;
  }

  @override
  Future<void> write(T tokens) async {
    writes++;
    final error = writeError;
    if (error != null) {
      throw error;
    }
    stored = tokens;
    log.add('write');
  }

  @override
  Future<void> delete() async {
    deletes++;
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    stored = null;
    log.add('delete');
  }
}
