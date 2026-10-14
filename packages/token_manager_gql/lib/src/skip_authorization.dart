import 'package:gql_exec/gql_exec.dart';

/// Marks a request that must be sent without tokens, such as a login.
///
/// A login or sign-up runs before any tokens exist, so asking the manager for
/// them would fail with `NotAuthenticated`. `TokenManagerLink` forwards a
/// request whose context holds this entry unchanged: it attaches no header,
/// never asks for tokens and never replays.
///
/// ```dart
/// final login = request.withContextEntry(const SkipAuthorization());
/// ```
///
/// {@category auth-failures}
final class SkipAuthorization extends ContextEntry {
  /// Creates the marker.
  const SkipAuthorization();

  @override
  List<Object?> get fieldsForEquality => const [];
}
