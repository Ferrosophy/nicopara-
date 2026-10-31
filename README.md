# nicopara

An unofficial niconico (ニコニコ動画) player for iOS, written in SwiftUI.

> **Unofficial.** This project is not affiliated with, endorsed by, or connected to
> DWANGO Co., Ltd. or niconico. "niconico" and related names are trademarks of their owners.

## Features

- Playback (HLS), quality and audio selection, picture in picture, background listening
- Login through the official niconico login page (the password is never seen by the app)
- Recommendations, search with the website's filters and sorting, genre rankings
- Following feed and list, uploader pages, series
- Watch later and history (synced with your account), plus local lists
- Danmaku (comments) overlay and list (display only, no posting)
- Inline translation of descriptions and danmaku (Google Translate, free, no key needed)
- Interface in Chinese, English and Japanese

There is **no download feature**, and paid or members-only content is not unlocked.

## Requirements

- iOS 26 or later
- [xtool](https://xtool.sh) with an iOS SDK, on Linux or WSL (no Mac needed)

## Building

```bash
bash scripts/build_ipa.sh
```

This writes an unsigned IPA to `xtool/`. Sign it with your own certificate to install it.

The app icon is not included in this repository. To use one, add a 1024×1024 PNG to the
project and set `iconPath:` to it in `xtool.yml`.

The networking code lives in `NicoKit`, a separate Swift package that also builds and tests
on Linux:

```bash
cd NicoKit && swift test
```

## Notes

- The app talks to niconico's web APIs, which are not public and can change at any time.
- Translation uses Google Translate's free web endpoint, which may be rate-limited or stop working.

## License

[GNU General Public License v3.0](LICENSE)
