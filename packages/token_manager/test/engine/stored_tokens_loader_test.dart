import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/engine/stored_tokens_loader.dart';

import '../helpers/fake_token_store.dart';

void main() {
  late FakeTokenStore<String> store;
  late int epoch;
  late List<String> loaded;
  late StoredTokensLoader<String> loader;

  setUp(() {
    store = FakeTokenStore<String>('stored');
    epoch = 0;
    loaded = [];
    loader = StoredTokensLoader<String>(
      store: store,
      epoch: () => epoch,
      onLoaded: loaded.add,
    );
  });

  test('load hands the stored tokens to the callback', () async {
    await loader.load();

    expect(loaded, ['stored']);
  });

  test('load reads the store once for concurrent callers', () async {
    await Future.wait([loader.load(), loader.load()]);

    expect(store.reads, 1);
    expect(loaded, ['stored']);
  });

  test('load does not read again after it succeeded', () async {
    await loader.load();
    await loader.load();

    expect(store.reads, 1);
  });

  test('an empty store calls nothing back', () async {
    store.stored = null;

    await loader.load();

    expect(loaded, isEmpty);
  });

  test('load rethrows a failed read', () async {
    store.readError = Exception('disk');

    await expectLater(loader.load(), throwsException);
  });

  test('a failed read is retried by the next load', () async {
    store.readError = Exception('disk');
    await expectLater(loader.load(), throwsException);
    store.readError = null;

    await loader.load();

    expect(store.reads, 2);
    expect(loaded, ['stored']);
  });

  test('markLoaded suppresses a later read', () async {
    loader.markLoaded();

    await loader.load();

    expect(store.reads, 0);
    expect(loaded, isEmpty);
  });

  test('a read that finishes after an epoch change is dropped', () async {
    final gate = Completer<void>();
    store.readGate = gate;
    final loading = loader.load();
    await Future<void>.delayed(Duration.zero);

    epoch++;
    gate.complete();
    await loading;

    expect(loaded, isEmpty);
  });

  test('a failed read does not undo a markLoaded made meanwhile', () async {
    final gate = Completer<void>();
    store.readGate = gate;
    store.readError = Exception('disk');
    final first = loader.load();
    final failure = expectLater(first, throwsException);
    await Future<void>.delayed(Duration.zero);

    loader.markLoaded();
    gate.complete();
    await failure;
    await loader.load();

    expect(store.reads, 1);
  });

  test('loadUnlessBroken swallows an exception from the store', () async {
    store.readError = Exception('disk');

    await loader.loadUnlessBroken();

    expect(loaded, isEmpty);
  });

  test('loadUnlessBroken retries after a swallowed failure', () async {
    store.readError = Exception('disk');
    await loader.loadUnlessBroken();
    store.readError = null;

    await loader.load();

    expect(loaded, ['stored']);
  });

  test('loadUnlessBroken does not swallow an Error', () async {
    store.readError = null;
    final failing = StoredTokensLoader<String>(
      store: store,
      epoch: () => epoch,
      onLoaded: (_) => throw StateError('bug'),
    );

    await expectLater(failing.loadUnlessBroken(), throwsStateError);
  });
}
