# Streams

`authorizeStream` opens a stream that needs valid tokens, and reopens it once
if the server rejects them before the first event.

```dart
import 'package:token_manager/token_manager.dart';

Stream<String> watch(TokenManager<TokenSet> manager) {
  return manager.authorizeStream<String>(
    (tokens) => Stream.value('event for ${tokens.accessToken}'), // your stream
    isAuthFailure: (error) => error is StateError, // e.g. gRPC UNAUTHENTICATED
  );
}
```

## Contract

- **Lazy.** Nothing is opened until the stream is listened to.
- **Single subscription.** The result supports one listener.
- **Replay before the first event only.** An auth failure before any event is
  reported as rejected, the tokens are renewed and `open` runs a second time.
  Once an event was delivered, or after one replay, errors are forwarded as
  they are: replaying mid-stream would duplicate or lose data.
- **No replacement, no replay.** If renewing returns the same tokens, the
  original error is the stream's error.
- **At most two `open` calls**, and never after the listener cancelled.
- **A throwing `open`** becomes the stream's error and ends it.

## Pause, resume and cancel

Library code never consumes a source with `await for`: that hides the
subscription, so pause, resume and cancel could not reach the source. The
relay subscribes with `listen` and forwards control.

```dart
import 'package:token_manager/token_manager.dart';

Future<void> controlled(TokenManager<TokenSet> manager) async {
  final subscription = manager
      .authorizeStream<String>(
        (tokens) => Stream.value(tokens.accessToken),
        isAuthFailure: (error) => error is StateError,
      )
      .listen(print);

  subscription.pause(); // pauses the source stream
  subscription.resume(); // resumes it
  await subscription.cancel(); // cancels the source and stops any replay
}
```

If the listener pauses while the stream is being (re)opened, the new source
starts paused.

## Where to go next

- [Refreshing](refreshing.md) — what happens during the renewal.
- [Testing](testing.md) — driving the manager in tests.
