# selumn

[简体中文](README.zh.md) | English

A personal diary app built with Flutter and Rust, with a Vue / TipTap editor. This fork is maintained by [MangataYu](https://github.com/MangataYu) and focuses on organizing writing with tags and making everyday navigation simpler.

Based on [Moodiary by ZhuJHua](https://github.com/ZhuJHua/moodiary). This is an independently maintained fork, not an official Moodiary release.

[Downloads](https://github.com/MangataYu/selumn/releases) · [Source code](https://github.com/MangataYu/selumn) · [Roadmap (Chinese)](TODO.md)

![Flutter](https://img.shields.io/badge/Flutter-3.47.2-blue)
[![License](https://img.shields.io/github/license/MangataYu/selumn)](LICENSE)

The repository is named **selumn**. The app and existing APK filenames currently use **Selume**.

## What this fork changes

- **Tags in your writing**: type `#work/project` followed by a space to create a tag. Suggestions help you reuse existing tags, and `/` expresses a hierarchy.
- **Tag management**: search, rename, or delete tags and their descendants, and adjust their order within each level.
- **Sidebar filters**: browse a collapsible tag tree or filter for untagged entries and entries containing images, links, or audio. Parent tags include entries under their descendants.
- **Sidebar navigation**: access media, maps, the entry graph, calendar, and assistant from one sidebar.
- **Writing overview**: see entry and tag counts, days of use, and a writing heatmap in the sidebar. Select a date to view its entry and character counts.
- **Updates from this repository**: Android's “Check for updates” uses this fork's GitHub Releases.

See [TODO.md](TODO.md) for planned work and validation still to do. Quick capture from other apps, a redesigned feelings system, and AI organization after import are future work.

## Diary features

- **Rich text and media**: write entries with images, audio, and video.
- **Search and tags**: full-text search and tag-based filtering.
- **Themes and fonts**: light and dark modes, multiple color schemes, and imported fonts, including variable fonts.
- **App lock**: password protection with biometric unlock.
- **Import, export, and sharing**: export Markdown, Word, PDF, or long images; import Markdown archives and local backups.
- **Backup and sync**: WebDAV, S3 / MinIO, and LAN sync, with optional end-to-end encryption.
- **Weather and places**: attach weather and saved places to entries and view your footprints on a map.
- **Mood tracking**: manually select or change the mood for each diary entry.
- **Assistant**: connect an OpenAI- or Anthropic-compatible provider for chat and diary tools.

## Download and use

Look for this fork's published packages on [selumn Releases](https://github.com/MangataYu/selumn/releases). The current CI workflow builds **Android ARM64 APKs**; release notes identify test pre-releases. If no suitable package is available, use the source build instructions below.

The core diary works offline. Optional online services require their own configuration. Android's in-app update check looks for a newer stable release in this repository; download test pre-releases directly from the release page.

## Development

The Flutter app is in `mobile/`; shared packages are in `packages/`. Use the Flutter version pinned in [.fvmrc](.fvmrc), the Rust toolchains declared in each native package, and the Node / pnpm requirements in the [editor package](packages/feature_base/moodiary_editor/editor/package.json). Install Git LFS, FVM, and the platform build tools before building.

With those prerequisites installed, run from the repository root:

```sh
git lfs pull
fvm use
fvm dart tool/task.dart setup
fvm dart tool/task.dart run
```

Connect a device or start an emulator before running the app. See [AGENTS.md](AGENTS.md) for repository structure and validation commands, and the [editor README](packages/feature_base/moodiary_editor/README.md) for editor development.

## Credits and license

Thanks to [ZhuJHua](https://github.com/ZhuJHua), [Moodiary](https://github.com/ZhuJHua/moodiary), and all [upstream contributors](https://github.com/ZhuJHua/moodiary/graphs/contributors) for the original project. Changes in this fork are maintained by [MangataYu](https://github.com/MangataYu).

This project continues to use the [GNU Affero General Public License v3.0](LICENSE). Existing copyright and license notices are retained. This README was adapted for selumn on **2026-09-21**.

The [upstream documentation](https://docs.moodiary.net) describes Moodiary; this fork's interface and workflows may differ. To support the original author, visit the [upstream project](https://github.com/ZhuJHua/moodiary#-sponsor).

<details>
<summary>Original project's sponsors</summary>

The following acknowledgements are retained from Moodiary and refer to support for the original project.

<!-- sponsors:start -->
朱东杰, [dsxksss](https://github.com/dsxksss), 不对味的雪碧, [xiaoxianzi-99](https://github.com/xiaoxianzi-99), Lucci, [Higanoneko](https://github.com/Higanoneko), h, 大作文
<!-- sponsors:end -->

</details>
