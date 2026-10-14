import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager_grpc/token_manager_grpc.dart';

/// Attaches the token as `authorization: Bearer <token>`.
class BearerDelegate extends RefreshInterceptorDelegate<String> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(String? tokens) => grpc.CallOptions(
    metadata: {if (tokens != null) 'authorization': 'Bearer $tokens'},
  );
}
