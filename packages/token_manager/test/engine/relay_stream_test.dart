import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/engine/relay_stream.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

final class _Source {
  _Source(this.tokens) {
    controller.onCancel = () => cancelled = true;
  }

  final String tokens;
  final StreamController<int> controller = StreamController<int>();
  bool cancelled = false;

  Future<void> close() => controller.close();
}

void main() {
  late List<_Source> sources;
  late int renewCalls;

  setUp(() {
    sources = [];
    renewCalls = 0;
  });

  tearDown(() async {
    for (final source in sources) {
      await source.close();
    }
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Stream<int> relayed({
    Future<String> Function()? acquire,
    Future<String> Function(String rejected)? renew,
  }) {
    return RelayStream<String, int>(
      acquire: acquire ?? () async => 'a',
      renew:
          renew ??
          (rejected) async {
            renewCalls++;
            return 'b';
          },
      open: (tokens) {
        final source = _Source(tokens);
        sources.add(source);
        return source.controller.stream;
      },
      isAuthFailure: (error) => error is _Unauthorized,
    ).stream;
  }

  test('opens the source only when listened to and relays events', () async {
    final stream = relayed();
    await settle();
    expect(sources, isEmpty);

    final received = <int>[];
    final subscription = stream.listen(received.add);
    await settle();
    sources.single.controller
      ..add(1)
      ..add(2);
    await settle();

    expect(sources.single.tokens, 'a');
    expect(received, [1, 2]);
    await subscription.cancel();
  });

  test('cancelling before the token arrives never opens the source', () async {
    final token = Completer<String>();
    final subscription = relayed(acquire: () => token.future).listen((_) {});
    await settle();

    await subscription.cancel();
    token.complete('a');
    await settle();

    expect(sources, isEmpty);
  });

  test('a pause requested before the source opens is applied to it', () async {
    final token = Completer<String>();
    final subscription = relayed(acquire: () => token.future).listen((_) {});
    await settle();

    subscription.pause();
    token.complete('a');
    await settle();

    expect(sources.single.controller.isPaused, isTrue);
    await subscription.cancel();
  });

  test('pause and resume reach the source', () async {
    final subscription = relayed().listen((_) {});
    await settle();

    subscription.pause();
    expect(sources.single.controller.isPaused, isTrue);

    subscription.resume();
    expect(sources.single.controller.isPaused, isFalse);
    await subscription.cancel();
  });

  test('cancel reaches the source', () async {
    final subscription = relayed().listen((_) {});
    await settle();

    await subscription.cancel();

    expect(sources.single.cancelled, isTrue);
  });

  test(
    'an auth failure before the first event renews and reopens once',
    () async {
      final received = <int>[];
      final errors = <Object>[];
      final subscription = relayed().listen(received.add, onError: errors.add);
      await settle();

      sources[0].controller.addError(const _Unauthorized());
      await settle();
      sources[1].controller.add(7);
      await settle();

      expect(sources.map((source) => source.tokens), ['a', 'b']);
      expect(sources[0].cancelled, isTrue);
      expect(renewCalls, 1);
      expect(received, [7]);
      expect(errors, isEmpty);
      await subscription.cancel();
    },
  );

  test('an auth failure after the first event is forwarded', () async {
    final received = <int>[];
    final errors = <Object>[];
    final subscription = relayed().listen(received.add, onError: errors.add);
    await settle();

    sources.single.controller
      ..add(1)
      ..addError(const _Unauthorized());
    await settle();

    expect(received, [1]);
    expect(errors.single, isA<_Unauthorized>());
    expect(renewCalls, 0);
    await subscription.cancel();
  });

  test('a second auth failure after the replay is forwarded', () async {
    final errors = <Object>[];
    final subscription = relayed().listen((_) {}, onError: errors.add);
    await settle();

    sources[0].controller.addError(const _Unauthorized());
    await settle();
    sources[1].controller.addError(const _Unauthorized());
    await settle();

    expect(errors.single, isA<_Unauthorized>());
    expect(renewCalls, 1);
    await subscription.cancel();
  });

  test('the error is forwarded and the stream ends when renew returns the '
      'same tokens', () async {
    final errors = <Object>[];
    var done = false;
    final subscription = relayed(renew: (rejected) async => rejected).listen(
      (_) {},
      onError: errors.add,
      onDone: () => done = true,
    );
    await settle();

    sources.single.controller.addError(const _Unauthorized());
    await settle();

    expect(errors.single, isA<_Unauthorized>());
    expect(done, isTrue);
    expect(sources, hasLength(1));
    await subscription.cancel();
  });

  test(
    'a failure to acquire tokens becomes an error and ends the stream',
    () async {
      final errors = <Object>[];
      var done = false;
      final subscription = relayed(
        acquire: () async => throw Exception('offline'),
      ).listen((_) {}, onError: errors.add, onDone: () => done = true);
      await settle();

      expect(errors.single, isA<Exception>());
      expect(done, isTrue);
      expect(sources, isEmpty);
      await subscription.cancel();
    },
  );

  test('the relayed stream ends when the source ends', () async {
    var done = false;
    final subscription = relayed().listen((_) {}, onDone: () => done = true);
    await settle();

    await sources.single.controller.close();
    await settle();

    expect(done, isTrue);
    await subscription.cancel();
  });

  test(
    'nothing surfaces after cancel when the source or acquire is late',
    () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final subscription = relayed().listen((_) {});
        await settle();
        final source = sources.single;
        await subscription.cancel();
        source.controller
          ..add(1)
          ..addError(const _Unauthorized());
        await settle();

        final token = Completer<String>();
        final late = relayed(acquire: () => token.future).listen((_) {});
        await settle();
        await late.cancel();
        token.completeError(Exception('offline'));
        await settle();
      }, (error, stackTrace) => uncaught.add(error));

      expect(uncaught, isEmpty);
    },
  );
}
