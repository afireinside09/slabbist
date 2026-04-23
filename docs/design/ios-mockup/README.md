# Slabbist iOS mockup — reference

Source: Claude artifact share
`https://claude.ai/design/p/d88d0db2-a714-4320-a57a-4ce43975ef6f?file=Slabbist+iOS.html`

## What's here

- `Slabbist-iOS.html` — the self-contained artifact. Open in a browser to see the live mockup.
- `unpack.py` — extractor for the artifact's inline `__bundler` manifest.
- `unpacked/*.jsx` — the four React/JSX source files that define the design language and every screen. These are the primary reference.
- `unpacked/*.woff2` / `*.js` — font files and the React/Babel/Tailwind vendor bundles (gitignored; regenerable via `python3 unpack.py`).
- `design-brief.md` — distilled token set, typography, components, screen archetypes, and SwiftUI mapping notes. **Read this first** when implementing a screen.

## Rebuild the unpacked assets

```bash
cd docs/design/ios-mockup
python3 unpack.py
```

Idempotent; rewrites everything under `unpacked/`.

## Source of truth

The JSX files are the reference. When something in the brief is unclear, go back to the JSX — exact tokens, animations, and layout decisions live there.
