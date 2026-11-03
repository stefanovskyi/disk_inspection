# SpaceLens Hyperspace variants

Hyperspace is the selected theme. **Holo Pulse** is the current default: Hologram's
colors, translucency, edge weights, glow, and starfield, with Pulse's curved hover
tracer and timing. The source variations remain available for comparison.

The user's design constraint is explicit: **do not use the square hover brackets**.
Hover feedback follows the annular folder sector itself, with no detached target
marker. Byte proportions, hierarchy depth, and navigation use the existing chart.

| Variant | Surface | Hover |
| --- | --- | --- |
| Holo Pulse | Hologram's material and palette | Pulse's curved edge tracer |
| Hologram | Original Hyperspace glass-like edges and translucent bands | A narrow light sweep within the sector |
| Nebula | Fuller luminous bands, softer glow, and a richer static starfield | A soft light wave across the sector's width |
| Pulse | Crisp energy contours, quiet interiors, and a sparse starfield | A short tracer along the sector's outer arc |

All four share the same blue palette, branch colors, capacity outline, ranked
directory panel, and chart placement. Holding the structure constant makes the
lighting and motion differences easier to compare.

## Appearance

**Dark** preserves Hologram's original palette. **Slate** replaces the bright light
appearance with opaque blue-gray surfaces and a subtle gradient. The page,
chart hub, free-space label, hover card, and switcher all use that palette. The
native window chrome stays dark when the content changes to Slate.

Theme surfaces must never be solid white. The Slate theme uses surfaces in the
`#8FA4B4` to `#B6C7D4` range, with dark blue text and darker chart edges. Hover light
uses ice blue rather than pure white. The main app's existing palette is unchanged.

## Open

```bash
make chart-preview
```

The native lab supports hover, folder drill-down, breadcrumbs, keyboard variant
cycling, Dark/Slate appearance, motion controls, and disk/folder samples.
The launcher builds a separate preview app in `.build/` with its own identity,
so it can run beside an existing SpaceLens session.

Double-click `index.html` for the interactive Canvas comparison. Hover a folder
or use **Try hover effect** to replay the animation. The `?variant=` values are
`holo-pulse` (default), `hologram`, `nebula`, and `pulse`. Use `?appearance=slate`
for the muted appearance; older `appearance=light` links also open Slate.

Hover animation lasts at most 1.2 seconds, then its timeline stops. Native updates
are capped at 30 per second during that event. Changing the hovered sector, root,
or variant discards the old effect. **Motion off** and the system's **Reduce Motion**
setting use a static highlight. Stars remain static.

Both previews use invented 480.98 GB / 512 GB disk data, with 31.02 GB free,
and a 39 GB folder sample. Finder and Terminal actions are inactive for sample
data. The gallery starts no scan and persists no preferences.

## Isolation

Branch: `prototype/storage-map-styles`. The gallery is opt-in through
`--chart-style-prototype`; normal app launches keep their existing presentation.
An optional `hyperspaceVariant` environment value activates the new material
only in the lab. The filesystem scanner and `SunburstLayout` are unchanged.

## Reproduce

```bash
make build
.build/debug/SpaceLens --chart-style-prototype --export-chart-previews "$PWD/docs/prototypes/chart-styles/images"
python3 Scripts/build_space_preview.py
```

The eight PNGs are native SwiftUI renders at 1080 × 730 points, at 1.5× scale.
Filenames ending in `-light.png` now contain the Slate appearance.
The exporter also writes `space-scenes.json` with native scene angles and folder
navigation targets. The Python helper embeds that data into
`space-preview.template.html` to produce the self-contained `index.html`.

The native and browser renderers implement the same variants separately.
Use the native lab or PNGs to judge the final macOS appearance.
