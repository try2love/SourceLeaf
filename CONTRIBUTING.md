# Contributing to SourceLeaf

Thank you for improving SourceLeaf. Contributions must remain available for personal, educational, public-research, and other noncommercial purposes under the project's license.

## Developer Certificate of Origin

Every commit must include a `Signed-off-by` trailer:

```text
Signed-off-by: Your Name <you@example.com>
```

Use `git commit -s` to add it. By signing off, you certify the Developer Certificate of Origin in `DCO.txt`.

## Before opening a pull request

```bash
swift test
swift build -c release
```

- Keep API keys, personal paths, paper content, chat histories, and build artifacts out of commits.
- Add tests for parsing, patch safety, compilation coordination, and provider response handling.
- Preserve English and Simplified Chinese localization for user-facing strings.
- Document third-party code or assets in `THIRD_PARTY_LICENSES.md`.
