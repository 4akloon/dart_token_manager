import 'dart:async';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

/// A terminating link that answers each request with a scripted outcome and
/// records what it was sent.
final class FakeTerminalLink extends Link {
  /// Answers request number `i` with `outcomes[i]`: a [Response] is emitted
  /// as an event, a [List] emits each of its items in that way, anything else
  /// is emitted as an error event, and the stream then ends.
  /// A request past the script gets a stream that stays open.
  FakeTerminalLink([this._outcomes = const []]);

  final List<Object> _outcomes;

  /// The requests received, in order.
  final List<Request> requests = [];

  /// The controller behind the stream of each request, in order.
  final List<StreamController<Response>> controllers = [];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final index = requests.length;
    requests.add(request);
    final controller = StreamController<Response>();
    controllers.add(controller);
    if (index < _outcomes.length) {
      final outcome = _outcomes[index];
      for (final event in outcome is List<Object> ? outcome : [outcome]) {
        _emit(controller, event);
      }
      unawaited(controller.close());
    }
    return controller.stream;
  }

  void _emit(StreamController<Response> controller, Object event) {
    switch (event) {
      case final Response response:
        controller.add(response);
      case final Object error:
        controller.addError(error);
    }
  }

  /// The `Authorization` header of request number [index], if any.
  String? authorizationOf(int index) => requests[index].context
      .entry<HttpLinkHeaders>()
      ?.headers['Authorization'];
}
