## 0.1.0 - 2026-03-27

### Added
- Initial gRPC integration package for `token_manager`.
- `RefreshInterceptor<T>` for unary and streaming retry on unauthenticated errors.
- `RefreshInterceptorDelegate<T>` extension point for call metadata construction.
- Async response wrappers for transparent retry handoff and cancellation.
- Package documentation and runnable example.
