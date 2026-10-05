# Noto Emoji

Bundled monochrome variable font from [Google Fonts](https://github.com/google/fonts/tree/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoemoji).

- Source: `ofl/notoemoji/NotoEmoji[wght].ttf`, saved unchanged as `NotoEmoji.ttf`.
- Upstream revision: `8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5`.
- SHA-256: `de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551`.
- License: SIL Open Font License 1.1, in `NotoEmoji-OFL.txt`. The first line labels the font in Flutter's license page; the upstream copyright and license follow unchanged.

Flutter mood widgets and the web editor use this same source font at weight 400. The editor build imports the file through Vite and packages it locally for offline use. Keep the editor build hook dependency in sync if this source path changes.
