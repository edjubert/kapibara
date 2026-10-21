<p align="center">
  <img src="docs/logo.svg" alt="Kapibara logo: a capybara in profile" width="160">
</p>

# kapibara

Menu bar app for [Kapitsa](https://github.com/nace-ai/kapitsa), the local
Apple Silicon inference engine. Start and stop the server, see the
downloaded models, download new ones, and watch prompt and generation
activity, all from the macOS menu bar.

Named after Pyotr Kapitsa, the physicist the engine is named for. The
mascot is a capybara; it keeps an eye on your GPU.

```
kapibara/
├── app/      SwiftUI macOS menu bar app (Kapibara.app), embeds the CLI
└── Makefile  release tooling
```

## DISCLAIMER: local data only

Everything here is computed from the **local Kapitsa installation** on
this machine (`~/.cache/kapitsa/`, the server on `127.0.0.1`). It is not
the account-wide truth: usage on other machines is not counted, and
Kapitsa exposes no public endpoint to fetch anything. The server's own
chat page is the authoritative interface.

## Quick start

```bash
# Requires the kapitsa CLI: brew install nace-ai/tap/kapitsa

# macOS menu bar app (Xcode Command Line Tools required)
make -C app install-app
```

The app saves the last successful downloaded-model list, catalog and
context limits to `~/.kapibara/models.json`. It displays this cache
immediately at launch, then refreshes the downloaded models and catalog
independently in the background. Refresh and completed downloads update
the cache; a failed refresh keeps the last successful data visible.

## Release

```bash
make release
```

Builds into `dist/`:

- `Kapibara.app` and a zipped `Kapibara-<version>-macos-arm64.zip`
