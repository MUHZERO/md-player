## Summary

Describe the user-visible change and compatibility impact.

## Validation

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Android tests/builds when relevant
- [ ] Generated Pigeon files are current when the schema changed

## Safety

- [ ] No credentials, signed URLs, private media, device serials, or raw reports
- [ ] No product behavior was changed without a focused regression test
