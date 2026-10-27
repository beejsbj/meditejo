# Meditejo

Meditejo is Burooj’s personal meditation app, bringing courses and practice material into one calm place. The fork is under active development: the local timer works offline, and the catalogue is currently empty pending source integrations. *Meditejo* is Esperanto for “place of meditation”.

Based on [Medito](https://github.com/meditohq/medito-app) by the [Medito Foundation](https://meditofoundation.org). Meditejo is an independent fork. Medito’s audio catalogue is not included in the fork’s intended content library.

## Build

See [docs/fork/BUILD.md](docs/fork/BUILD.md) for the toolchain, code generation, build and signing instructions. The Dart package retains its internal name `medito`.

## Branding

The launcher icon is the **shelter** (a roof over a resting pebble) in the Tidewater palette, Meditejo's fixed house mark. Its geometry is frozen in [assets/branding/house_mark.json](assets/branding/house_mark.json); regenerate every platform's icon from it with:

```sh
uv run tools/meditejo/branding/make_icons.py
```

This writes the Android adaptive icon (with its Android 13 monochrome layer), legacy mipmaps, notification and widget glyphs, the iOS app and widget icons, and the app's own copies. Inside the app, Home shows a different generated mark each day, which can be pinned; see `lib/services/identity/`. No third-party art or fonts are included.

## Licence

App code is licensed under [AGPL-3.0](LICENSE). Upstream notices are preserved. Source: [beejsbj/meditejo](https://github.com/beejsbj/meditejo).
