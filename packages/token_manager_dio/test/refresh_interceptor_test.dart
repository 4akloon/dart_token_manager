// The deprecated name is the subject of this test.
// ignore_for_file: deprecated_member_use_from_same_package
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'helpers/bearer_delegate.dart';
import 'helpers/dio_fixture.dart';
import 'helpers/fake_http_adapter.dart';

void main() {
  test('the deprecated name is a DioTokenInterceptor', () {
    final interceptor = RefreshInterceptor<TokenSet>(
      manager: TokenManager<TokenSet>.create(
        store: InMemoryTokenStore<TokenSet>(null),
      ),
      delegate: const BearerDelegate(),
    );

    expect(interceptor, isA<DioTokenInterceptor<TokenSet>>());
  });

  test('the deprecated name attaches the token to a request', () async {
    final adapter = FakeHttpAdapter(accepted: 'Bearer old');
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        RefreshInterceptor<TokenSet>(
          manager: TokenManager<TokenSet>.create(
            store: InMemoryTokenStore<TokenSet>(DioFixture.initial),
          ),
          delegate: const BearerDelegate(),
        ),
      );

    final response = await dio.get<Object?>('/me');

    expect(response.statusCode, 200);
    expect(adapter.requests.single.authorization, 'Bearer old');
  });
}
