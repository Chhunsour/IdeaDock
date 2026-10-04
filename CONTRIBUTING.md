# Contributing to IdeaDock

Thank you for your interest in contributing to IdeaDock!

## Development Requirements

- macOS 14.0 (Sonoma) or later
- Apple Swift 6.0+ Command Line Tools
- Git

## Building & Testing Locally

IdeaDock is self-contained and has zero third-party package dependencies:

```bash
# Run the verification self-tests
./scripts/test.sh

# Build the signed macOS application bundle
./scripts/build.sh
```

## Pull Request Guidelines

1. Create a feature branch (`git checkout -b feat/my-improvement`).
2. Ensure `./scripts/test.sh` passes completely with zero errors.
3. Follow the existing Swift coding style and architecture conventions.
4. Submit a Pull Request describing your changes and motivations.
