# SpaceLens Holo Pulse preview

**Holo Pulse is the only storage-map style and is used by normal app launches.**
The other styles, renderer branches, switchers, and screenshots have been removed.
Earlier exploration remains in Git history.

The native renderer lives in `Sources/SpaceLens/Views/HoloPulse/`. It combines
translucent bands, fine luminous edges, a static starfield, and a curved hover
tracer. The production `ChartPanel` and sample harness share `StorageMapPanel`.
The existing sidebar, inspector, Finder/Terminal actions, navigation, accessibility
labels, capacity proportions, and transparent missing descendants remain intact.
The inspector's ranked colors follow the chart's branch palette.

Hover follows the annular sector; there are no square brackets. Animation settles
after 1.2 seconds, runs at at most 30 frames per second, and respects macOS Reduce
Motion. Nothing animates continuously while the pointer is idle.

## Appearance

Dark uses a navy chart surface and cyan-led branch colors. Light appearance uses
Slate throughout the app: blue-gray surfaces from `#8FA4B4` to `#B6C7D4`, dark blue
text, and darker chart edges. Theme surfaces never use solid white. Hover light
uses ice blue. The sample harness keeps native controls dark while selecting Slate.

## Preview

```bash
make chart-preview
```

The sample harness uses invented data and a separate bundle identity. It supports
Dark/Slate appearance, motion controls, disk/folder samples, hover, folder
navigation, breadcrumbs, and row selection. Finder and Terminal actions are
inactive for invented paths. There is no style selection.

To inspect the normal application UI under the separate preview identity, close
the sample preview and run `Scripts/preview_chart_styles.sh --app`. This preserves
any existing SpaceLens process and its in-memory scan cache.

The self-contained `index.html` supports the same chart sample and curved tracer.
Use `?appearance=slate` for Slate; older `appearance=light` links also work.
It is a browser approximation; the two native PNGs render the production panel.

## Regenerate

```bash
make build
.build/debug/SpaceLens --chart-style-prototype --export-chart-previews "$PWD/docs/prototypes/chart-styles/images"
python3 Scripts/build_space_preview.py
```

`images/holo-pulse-dark.png` and `images/holo-pulse-light.png` are SwiftUI renders
of `StorageMapPanel` at 1080 × 730 points and 1.5× scale. The `-light.png` file uses
Slate. `space-scenes.json` contains native scene angles and navigation targets;
the Python helper embeds it into `space-preview.template.html` as `index.html`.

## Verify

```bash
make build
make test
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

Builds stay local; this change does not publish or release the application.
