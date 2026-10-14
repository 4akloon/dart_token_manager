# Clients

`TokenManagerLink` is a plain `gql_link` `Link` and depends on no client, so
the link from [Getting Started](getting_started.md) serves every client built
on `gql_link`. This page shows where to hand it over.

## graphql

```dart
import 'package:gql_link/gql_link.dart' as gql;
import 'package:graphql/client.dart';

GraphQLClient buildClient(gql.Link link) =>
    GraphQLClient(link: link, cache: GraphQLCache());
```

An anonymous operation puts `SkipAuthorization` in its context:

```dart
import 'package:graphql/client.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

MutationOptions loginOptions(String document) => MutationOptions(
  document: gql(document),
  context: Context().withEntry(const SkipAuthorization()),
);
```

## graphql_flutter

`graphql_flutter` uses the same `GraphQLClient`; it only adds a widget layer.
Build the client as above and give it to `GraphQLProvider` in a
`ValueNotifier`:

```dart
final client = ValueNotifier(buildClient(link));

GraphQLProvider(client: client, child: const MyApp());
```

Do not use graphql_flutter's `AuthLink` in the chain: `TokenManagerLink` already
sets the header, and `AuthLink` cannot replay. Build the chain with
`Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(...)])` and pass it
as `link:` — never `AuthLink().concat(HttpLink(...))`.

## ferry

```dart
import 'package:ferry/ferry.dart';

Client buildClient(Link link) => Client(link: link);
```

`ferry` accepts `gql_link <2.0.0`, which matches this package's constraint. An
anonymous request is a `Request` with the entry in its context, as in
[Auth Failures](auth_failures.md).

## Subscriptions

Subscriptions need the split described in [Subscriptions](subscriptions.md) with
any of these clients.
