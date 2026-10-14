import 'package:test/test.dart';
import 'package:token_manager/src/in_memory_token_store.dart';

void main() {
  test('reads null when nothing was written', () async {
    expect(await InMemoryTokenStore<String>().read(), isNull);
  });

  test('reads the initial value', () async {
    expect(await InMemoryTokenStore<String>('seed').read(), 'seed');
  });

  test('reads what was written', () async {
    final store = InMemoryTokenStore<String>();

    await store.write('token');

    expect(await store.read(), 'token');
  });

  test('delete clears the stored value', () async {
    final store = InMemoryTokenStore<String>('token');

    await store.delete();

    expect(await store.read(), isNull);
  });
}
