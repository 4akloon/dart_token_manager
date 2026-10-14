# Concepts

The core is small: a manager, three interfaces you implement, and one engine
that holds the state. This page explains the rules the engine follows.

```dart
import 'package:token_manager/token_manager.dart';

Future<void> twoCallers(TokenManager<TokenSet> manager) async {
  // When a refresh is needed, both calls share it.
  final results = await Future.wait([
    manager.validToken(),
    manager.validToken(),
  ]);
  print(identical(results[0], results[1]));
}
```

## Layers

| Layer | Role |
|---|---|
| `TokenManager` | The public facade; every method delegates to the engine. |
| Engine (`lib/src/engine/`) | State, single-flight refresh, sessions. Internal. |
| `TokenStore`, `TokenRefresher`, `TokenInfo`, `Clock` | The seams you implement or replace. |

The core knows nothing about HTTP. A transport adapter attaches the header,
recognises an auth failure and replays once; it never refreshes by itself, it
asks the manager through `validToken` or `authorize`.

## Single-flight refresh

At most one refresh runs at a time. A caller that needs a refresh while one is
in flight awaits the same future instead of starting another. This matters
because refresh tokens are usually rotated: a second concurrent refresh would
present an already used token and be rejected.

While it runs, `states` emits `Refreshing` carrying the tokens being replaced.

## The rejected token is compared

A server rejects the tokens a request carried, but by the time the failure
arrives another caller may already have refreshed them. `validToken(rejected:)`
therefore compares the rejected tokens with the current ones by identity:

- they are the same object: they are refreshed;
- they differ: the current tokens are returned without a second refresh.

That is the whole replay rule of `authorize`: report the tokens that failed,
and use whatever comes back. If what comes back is the very same object (no
refresher, or nothing newer), the original failure is rethrown.

## Sessions

`setTokens`, `logout` and an `InvalidGrant` each start a new session
internally (an epoch counter). Work started for an earlier session is
discarded when it finishes: a refresh that was running during a logout cannot
write its tokens back and resurrect the old session. Callers that were already
waiting on that refresh still get an answer.

Store writes and deletes are serialized, so a `setTokens` and a finishing
refresh never interleave.

## Why no background timer

A timer needs a lifecycle (when to start, pause on app suspend, stop on
logout), keeps the isolate busy, and refreshes tokens nobody is about to use.
Refreshing on demand has none of those costs: the first call after the margin
pays one round trip, and every concurrent caller shares it. Proactive refresh
is planned for a later release.

## Where to go next

- [Refreshing](refreshing.md) — expiry, skew and failure types.
- [Storage](storage.md) — what happens when the store fails.
