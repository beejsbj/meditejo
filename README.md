# Meditejo

Meditejo is Burooj’s personal meditation app, bringing courses and practice material into one calm place. The fork is under active development: the local timer works offline, and the catalogue is currently empty pending source integrations. *Meditejo* is Esperanto for “place of meditation”.

Based on [Medito](https://github.com/meditohq/medito-app) by the [Medito Foundation](https://meditofoundation.org). Meditejo is an independent fork. Medito’s audio catalogue is not included in the fork’s intended content library.

## Build

See [docs/fork/BUILD.md](docs/fork/BUILD.md) for the toolchain, code generation, build and signing instructions. The Dart package retains its internal name `medito`.

## Branding

The current circle mark is an original placeholder. Edit [assets/branding/placeholder.svg](assets/branding/placeholder.svg), then run:

```sh
uv run scripts/regenerate_icons.py
```

This regenerates Flutter previews and logos, Android launcher/notification/widget resources, and iOS app/widget icons. The generator uses a solid background and SVG paths; no third-party art or fonts are included.

## Licence

App code is licensed under [AGPL-3.0](LICENSE). Upstream notices are preserved. Source: [beejsbj/meditejo](https://github.com/beejsbj/meditejo).
