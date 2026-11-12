# Shuck

**Shuck — housekeeping for Mac.**

Shuck is a free, open-source macOS app that keeps a Mac tidy:

- **File Cleanup** finds large files, files you haven't opened in months, developer junk (Xcode data, `node_modules`, package caches), and caches and logs.
- **Applications** uninstalls apps together with the files they leave behind.
- **Startup Items** shows what starts automatically and lets you turn off what you don't want.

You review everything before Shuck acts. Personal files go to the Trash, and Shuck keeps its own log so you can put them back.

## Status

Early development. The [latest release](https://github.com/nutabi/shuck/releases) has File Cleanup's four sub-tools. Large Files and Old Files list your largest files and those you haven't opened in a while, and move the files you choose to the Trash. Developer Junk and Caches & Logs list what apps and developer tools can rebuild, and delete it or clean it up with the tool's own command. History lists every run and puts trashed items back. Applications and Startup Items come next; see the [roadmap](docs/PRD.md#13-roadmap) and [CHANGELOG.md](CHANGELOG.md).

## Requirements

macOS 27 or later on a Mac with Apple Silicon. Shuck works offline, needs no account and doesn't ask for administrator rights.

## Documentation

- [Product requirements](docs/PRD.md): scope, safety model, requirements and roadmap.
- [AGENTS.md](AGENTS.md): instructions for AI coding agents that work on Shuck.

## License

Copyright © 2026 Nguyen Thai Binh

Shuck is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see [LICENSE](LICENSE) for details.

Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.
