# Selume brand assets

Selected on 2026-09-19: a violet pearl ribbon with a warm drop of light suspended just above the right-hand curved surface. The outer shape approaches a circle but retains a visible gap below the drop. The exact background color is **#6B5CFF**. The theme-color settings inside the app are unchanged.

## Canonical sources

- `selume-foreground.png`: the selected 1254 × 1254 transparent artwork, identical to `selume-near-drop-foreground.png`. Preserve its generated alpha and the gap beneath the light drop.
- `selume-icon.png`: the 1024 × 1024 opaque, full-bleed mobile icon. Do not bake platform corner masks into the master.
- `selume-monochrome.svg`: the simplified native silhouette with a transparent S-shaped fold and a rounded droplet, used for Android themed icons. Its `pearl-silhouette`, `pearl-monochrome`, and `pearl-droplet-light` paths are the source geometry for native vector companions.
- `selume-icon.svg`: simplified vector companion; the pearl PNG remains the visual master. Native gradients approximate the material and keep the rounded droplet and gap.
- [Selected edit and prompt](selume-near-drop-study.md).

## Platform resources

- Android adaptive foreground: 432 × 432 RGBA in `drawable-xxxhdpi`, representing 108 dp. The artwork uses a centered 216 px / 54 dp canvas to retain room for its soft light edges within the 66 dp safe circle. The bitmap alias applies no extra inset.
- Android monochrome: native vector with `evenOdd` fill, using the same 54 dp artwork canvas. The internal fold is transparent rather than a painted white line.
- Legacy Android launcher icons: lossless 48 / 72 / 96 / 144 / 192 px WebP, with rounded-square and round masks.
- Play Store: 512 × 512 opaque full-bleed PNG.
- iOS Icon Composer: `Moodiary.icon/Assets/frg.png` over `bg.svg`. Extra glass, specular and shadow effects remain disabled because the pearl lighting is already baked into the foreground. Project and asset-catalog identifiers stay compatible with the existing build.
- Splash screens: matching simplified native vectors on Android and iOS, centered on 288-unit canvases. Light/dark palettes preserve contrast.
- In-app About and export watermark: existing `MoodiaryLogo` API and SVG loading remain unchanged, consuming the updated light/dark vector assets.

## Production and validation

The selected artwork was edited with the built-in imagegen tool. Deterministic resizing, background compositing and platform exports use Sharp; the selected raster artwork is not regenerated when exporting. The native companions use editable SVG geometry.

Validation covers PNG/WebP dimensions and alpha, Android adaptive safe bounds, XML/SVG/JSON resource references, equivalent Android/iOS splash gradients, and exact iOS-layer composition against the icon master. A full Flutter build and physical-device check are still needed; no Flutter SDK is installed in this workspace.

Selume is a fork of Moodiary. Visible app-name text uses Selume while upstream attribution and compatibility-sensitive identifiers remain intact.
