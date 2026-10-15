# Recipes

Copy-paste solutions for the common token tasks in Dart and Flutter. Every
recipe is one page with the complete code, what it does and the mistakes to
avoid. The code of each page lives in `example/recipes/` of its package, is
analyzed with the rest of the workspace, and is tested without a network.

## Find the recipe for your task

| I want to... | Recipe |
|---|---|
| sign the user in and keep the tokens fresh | [Sign in and store the tokens](../packages/token_manager/doc/recipes/login_and_set_tokens.md) |
| keep the user signed in after a restart | [Keep the session in secure storage](../packages/token_manager/doc/recipes/secure_token_store.md) |
| show the sign-in screen when the session ends | [Send the user to sign-in when the session ends](../packages/token_manager/doc/recipes/session_expiry.md) |
| make sure the tokens are fresh when the app resumes | [Refresh the session on app resume](../packages/token_manager/doc/recipes/refresh_on_resume.md) |
| test code that uses tokens without a network | [Test code that uses tokens without a network](../packages/token_manager/doc/recipes/testing_without_network.md) |
| replace a hand-written Dio refresh interceptor | [Replace a hand-written refresh interceptor](../packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md) |
| keep the login and the refresh request free of tokens in Dio | [Skip auth for the login and refresh endpoints](../packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md) |
| add a bearer token and a refresh on 401 to `package:http` | [An authorized `http.Client`](../packages/token_manager_http/doc/recipes/authorized_client.md) |
| authorize unary and streaming gRPC calls | [Unary and streaming calls with one refresh](../packages/token_manager_grpc/doc/recipes/unary_and_streaming.md) |
| authorize GraphQL queries and subscriptions | [Queries and WebSocket subscriptions](../packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md) |

## By package

| Package | Use it for | Recipes |
|---|---|---|
| [`token_manager`](../packages/token_manager/README.md) | storage, refresh and session state in any Dart code | sign in, secure storage, session expiry, refresh on resume, testing |
| [`token_manager_dio`](../packages/token_manager_dio/README.md) | `dio` | replace an interceptor, skip auth endpoints |
| [`token_manager_http`](../packages/token_manager_http/README.md) | `package:http` | an authorized client |
| [`token_manager_grpc`](../packages/token_manager_grpc/README.md) | `package:grpc` | unary and streaming calls |
| [`token_manager_gql`](../packages/token_manager_gql/README.md) | GraphQL on `gql_link` | queries and subscriptions |

Start with the core recipe on signing in: every adapter recipe builds on a
`TokenManager`.
