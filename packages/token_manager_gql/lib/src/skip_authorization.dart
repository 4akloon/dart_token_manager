import 'package:gql_exec/gql_exec.dart';

/// Marks a request that must be sent without tokens, such as a login.
///
/// `TokenManagerLink` forwards a request whose context holds this entry
/// unchanged: it attaches no header, never asks for tokens and never replays.
final class SkipAuthorization extends ContextEntry {
  /// Creates the marker.
  const SkipAuthorization();

  @override
  List<Object?> get fieldsForEquality => const [];
}
