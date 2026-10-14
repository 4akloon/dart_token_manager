// The deprecated name is the subject of this test.
// ignore_for_file: deprecated_member_use_from_same_package
import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

import 'helpers/bearer_delegate.dart';
import 'helpers/fake_unary_invoker.dart';
import 'helpers/grpc_fixture.dart';

void main() {
  RefreshInterceptor<String> build() => RefreshInterceptor<String>(
    manager: TokenManager<String>.create(store: InMemoryTokenStore('t0')),
    delegate: const BearerDelegate(),
  );

  test('the deprecated name is a GrpcTokenInterceptor', () {
    expect(build(), isA<GrpcTokenInterceptor<String>>());
  });

  test('the deprecated name attaches the token to a unary call', () async {
    final invoker = FakeUnaryInvoker<String, String>();

    final response = build().interceptUnary<String, String>(
      GrpcFixture.method,
      'ping',
      grpc.CallOptions(),
      invoker.invoke,
    );
    await GrpcFixture.settle();
    invoker.calls.single.succeed('pong');

    expect(await response, 'pong');
    expect(invoker.calls.single.options.metadata, {
      'authorization': 'Bearer t0',
    });
  });
}
