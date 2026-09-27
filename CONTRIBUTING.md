# Contributing

Thank you for improving the RustaBase Dart SDK.

## Development

Install Dart 3, then run:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Keep each pull request focused. New behavior should include tests and public API changes should include documentation.

## Design boundary

The SDK follows the public RustaBase protocol and independently implements its Dart architecture. Do not introduce source, naming, compatibility aliases, or attribution from unrelated SDKs.