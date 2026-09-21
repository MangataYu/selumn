# Selume brand assets

Selected on 2026-09-19: a violet pearl ribbon with a warm drop of light suspended just above the right-hand curved surface. The outer shape approaches a circle but retains a visible gap below the drop. The exact background color is **#6B5CFF**. The theme-color settings inside the app are unchanged.

## Canonical sources

- `selume-foreground.png`: the selected 1254 × 1254 transparent artwork, identical to `selume-near-drop-foreground.png`. Preserve its generated alpha and the gap beneath the light drop.
- `selume-icon.png`: the 1024 × 1024 opaque, full-bleed mobile icon. Do not bake platform corner masks into the master.
- `selume-monochrome.svg`: the simplified native silhouette with a transparent S-shaped fold and a rounded droplet, used for Android themed icons. Its `pearl-silhouette`, `pearl-monochrome`, and `pearl-droplet-light` paths supply the original geometry for native vector companions; the in-app and splash vectors extend only the warm-color coverage described below.
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

### In-app and splash droplet

The light/dark in-app SVGs and Android/iOS splash vectors retain the original pearl silhouette, droplet size, neck, and natural direction. Do not shrink, straighten, or reshape the droplet. The drop remains suspended above the lower ribbon with its original transparent gap.

Only the warm-color coverage extends along the upper-right arc toward the crown, fading smoothly into the purple body before continuing down the original neck and droplet. The overlay follows the existing silhouette exactly. Keep the silhouette, central ribbon fold, body/fold gradients, canvas sizes, and platform transforms intact when adjusting this color coverage.

Keep all six resources in sync: `assets/brand/logo_{light,dark}.svg`, Android `{drawable,drawable-night}/ic_splash_icon.xml`, and iOS `LaunchImage.imageset/Launch{Light,Dark}.svg`. The launcher artwork retains its original geometry. Preview the logo at the About page size of 160 dp and the export watermark size of 22 dp, as well as on both splash backgrounds.

### Dark logo palette

The in-app logo and Android/iOS splash companions use the light palette's soft violet body on dark backgrounds, with the body/fold sRGB channels scaled to 88% and rounded to the nearest integer. The drop keeps the light palette's cream highlight and a brighter pale-gold tip so it reads as a light source against the darker body; do not dim the drop together with the body or introduce a separate orange/amber palette. Gradient coordinates, offsets, alpha, and geometry remain identical between themes. Keep these body/fold gradient stops in sync across `logo_dark.svg`, `drawable-night/ic_splash_icon.xml`, and `LaunchDark.svg`:

| Gradient | Start | Midpoint | End |
| --- | --- | --- | --- |
| Pearl body | `#ADA6D6` | `#7565B6` | `#4C3A7E` |
| Ribbon fold | `#D8CAA0` | `#A090C8` | `#69549B` |

The warm-light `drop` gradient runs horizontally from (720, 0) to (1112, 0), using these stops in both themes. The overlay's left closing edge is fully transparent. Keep warm RGB values even at zero alpha to avoid a dark fringe. SVG uses `stop-opacity` equal to alpha/255; Android encodes the same alpha as `#AARRGGBB`.

| Offset | Alpha (0–255) | Dark RGB | Light RGB |
| --- | --- | --- | --- |
| 0 | 0 | `#FFF6D8` | `#FFF6D8` |
| 0.24 | 128 | `#FFF6D8` | `#FFF6D8` |
| 0.54 | 255 | `#FFF6D8` | `#FFF6D8` |
| 0.82 | 255 | `#FFE6AF` | `#EDD29A` |
| 1 | 255 | `#F2CD86` | `#BE9250` |

The launcher artwork retains its existing colors.

## Production and validation

The selected artwork was edited with the built-in imagegen tool. Deterministic resizing, background compositing and platform exports use Sharp; the selected raster artwork is not regenerated when exporting. The native companions use editable SVG geometry.

Validation covers PNG/WebP dimensions and alpha, Android adaptive safe bounds, XML/SVG/JSON resource references, equivalent Android/iOS splash gradients, and exact iOS-layer composition against the icon master. A full Flutter build and physical-device check are still needed.

Selume is a fork of Moodiary. Visible app-name text uses Selume while upstream attribution and compatibility-sensitive identifiers remain intact.
