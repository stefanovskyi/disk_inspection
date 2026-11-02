# SpaceLens storage-map exploration

Question: how can SpaceLens feel like an outer-space instrument panel, with
laser light and animated hover feedback, while preserving an accurate hierarchy?

Branch: `prototype/storage-map-styles`. This is throwaway prototype code. No design
has been selected or promoted to main, and no implementation issue was supplied.

## Options

| Style | Direction | Tradeoff |
| --- | --- | --- |
| Classic | Current solid fills and original path-based colors | Baseline |
| Hyperspace | Starfield, blue holographic edges, reticle lock and sector sweep | Fine edges favor a dark appearance |
| Bridge | Amber/violet console, directory panel on the left, warm hover sweep | Solid tiles are visually denser |
| Lasers | Green/pink energy core, centered map, twin photon traces and impact halo | The most theatrical hover treatment |

The earlier Aurora, Prism, and Contour concepts remain available under **Earlier
concepts** in the native lab, and in `previous-concepts.html`. These are original
space-console designs inspired by cinematic science fiction. No movie artwork,
logos, characters, sound effects, or proprietary interface assets are bundled.

The treatments assign separate colors to top-level branches and retain each
branch's color through its descendants. They use the existing `SunburstScene`,
capacity calculation, size-proportional angles, depth limit, hit testing, hover
card, selection, and drill-down actions. Missing descendants remain empty. Thin
instrument ticks sit outside the capacity boundary; stars are static decoration.

Hovering starts a single 1.2-second effect, then the timeline stops until another
sector is entered. The native timeline runs at most 30 times per second during
that burst. Moving away removes the effect and cancels its task. The **Motion**
switch and system **Reduce Motion** replace animation with a static highlight.
Navigation and changing styles discard the old effect.

The gallery uses invented 480.98 GB / 512 GB disk data, with 31.02 GB free, and a
39 GB folder sample. It does not scan the filesystem or persist preferences.
Context-menu Finder and Terminal actions are inactive for sample data.

## Open

- Double-click `index.html` for the interactive Canvas comparison. Hover, click
  directories, or use **Try hover effect** to replay an animation. Arrow keys
  cycle styles; dark/light, motion, and disk/folder controls are available.
- Run `make chart-preview` for actual native hover, selection, drill-down,
  breadcrumbs, and deep-disk / shallow-folder samples.
- The launcher builds a separate ad-hoc-signed preview bundle in `.build/` with
  its own identity, so it can run beside an existing SpaceLens session.
- Launch the app normally for the existing application, with Classic unchanged.

The gallery is opt-in through `--chart-style-prototype`. The extra source is in
`Sources/SpaceLens/Views/ChartStylePrototype/`; the existing chart's rendering uses
an environment value that defaults to Classic. Normal app launches keep Classic.

## Regenerate native snapshots

```bash
make build
.build/debug/SpaceLens --chart-style-prototype --export-chart-previews "$PWD/docs/prototypes/chart-styles/images"
python3 Scripts/build_space_preview.py
```

The PNGs are SwiftUI `ImageRenderer` output at 1080 × 730 points, rendered at 1.5×.
They use sample data. The exporter also writes `space-scenes.json`, containing
native scene angles and folder navigation targets. The Python helper embeds that
data into `space-preview.template.html` to produce the self-contained `index.html`.
The browser and native renderers implement the same visual concepts separately;
judge final macOS appearance in the native lab or its PNGs.

## Choosing a direction

Pick a material, layout, and hover effect independently. A chosen design should
be implemented as a focused production change; the lab, fixtures, and unused
variants stay on this branch. No winner has been selected.
