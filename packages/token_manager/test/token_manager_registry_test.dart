import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

void main() {
  late TokenManagerRegistry registry;

  TokenManager<String> stringManager() =>
      TokenManager<String>.create(store: InMemoryTokenStore<String>());

  setUp(() => registry = TokenManagerRegistry());

  test('returns the manager registered under an id', () {
    final manager = stringManager();

    registry.register<String>('main', manager);

    expect(registry.get<String>('main'), same(manager));
    expect(registry.ids, ['main']);
  });

  test('keeps providers with different token types apart', () {
    final strings = stringManager();
    final sets = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(),
    );

    registry
      ..register<String>('legacy', strings)
      ..register<TokenSet>('modern', sets);

    expect(registry.get<String>('legacy'), same(strings));
    expect(registry.get<TokenSet>('modern'), same(sets));
  });

  test('rejects a second manager for the same id', () {
    registry.register<String>('main', stringManager());

    expect(
      () => registry.register<String>('main', stringManager()),
      throwsStateError,
    );
  });

  test('rejects an unknown id', () {
    expect(() => registry.get<String>('missing'), throwsStateError);
  });

  test('rejects a request for the wrong token type', () {
    registry.register<String>('main', stringManager());

    expect(() => registry.get<TokenSet>('main'), throwsStateError);
  });

  test('dispose disposes every manager and empties the registry', () async {
    final manager = stringManager();
    registry.register<String>('main', manager);

    await registry.dispose();

    await expectLater(
      manager.states,
      emitsInOrder([isA<Unauthenticated<String>>(), emitsDone]),
    );
    expect(registry.ids, isEmpty);
  });

  test('dispose disposes all of several managers', () async {
    final first = stringManager();
    final second = stringManager();
    registry
      ..register<String>('first', first)
      ..register<String>('second', second);

    await registry.dispose();

    await expectLater(first.states, emitsThrough(emitsDone));
    await expectLater(second.states, emitsThrough(emitsDone));
    expect(registry.ids, isEmpty);
  });

  test('a supertype of the token type is accepted', () {
    final manager = stringManager();
    registry.register<String>('main', manager);

    expect(registry.get<Object>('main'), same(manager));
  });
}
