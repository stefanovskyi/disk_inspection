# SpaceLens storage-map exploration

Question: how can the sunburst feel more dimensional and inviting while preserving
an accurate, readable filesystem hierarchy?

Branch: `prototype/storage-map-styles`. This is throwaway prototype code. No design
has been selected or promoted to main, and no implementation issue was supplied.

## Options

| Style | Direction | Tradeoff |
| --- | --- | --- |
| Classic | Current solid fills and original path-based colors | Baseline |
| Aurora | Radial lighting, luminous edges, compact ranked inspector | Bloom softens tiny boundaries |
| Prism | Beveled tiles, directional light, centered map, horizontal legend | More visual density |
| Contour | Translucent interiors, fine edges, directory list on the left | Structure is more prominent than filled area |

Aurora is the initial recommendation for the user's request for a less flat chart.
Prism offers crisper edges; Contour explores a quieter alternative. These are
design judgments, not a user-approved verdict.

The three new treatments assign separate colors to top-level branches and retain
each branch's color through its descendants. They use the existing `SunburstScene`,
capacity calculation, size-proportional angles, six-level depth limit, hit testing,
hover card, selection, and drill-down actions. Missing descendants remain empty.
No perspective distortion, exploded slices, continuous animation, or extra rings.

The gallery uses invented 480.98 GB / 512 GB disk data, with 31.02 GB free, and a
39 GB folder sample. It does not scan the filesystem or persist preferences.
Context-menu Finder and Terminal actions are inactive for sample data.

## Open

- Double-click `index.html` for switchable native snapshots in dark and light mode.
- Run `make chart-preview` for actual native hover, selection, drill-down,
  breadcrumbs, and deep-disk / shallow-folder samples.
- The launcher builds a separate ad-hoc-signed preview bundle in `.build/` with
  its own identity, so it can run beside an existing SpaceLens session.
- Launch the app normally for the existing application, with Classic unchanged.

The gallery is opt-in through `--chart-style-prototype`. The extra source is scoped
to `Sources/SpaceLens/Views/ChartStylePrototype/`; the existing chart's rendering
uses an environment value that defaults to Classic.

## Regenerate native snapshots

```bash
make build
.build/debug/SpaceLens --chart-style-prototype --export-chart-previews "$PWD/docs/prototypes/chart-styles/images"
```

The PNGs are actual SwiftUI `ImageRenderer` output from the prototype stage at
1080 × 730 points, rendered at 1.5×. They are not screenshots of a real scan.
The HTML comparison switches between those PNGs; native chart interaction is
available in `make chart-preview`.

## Choosing a direction

Pick a material and a layout independently. For example, Aurora's bands can pair
with Prism's centered layout. A chosen design should be implemented as a focused
production change; the lab, fixtures, and unused variants stay on this branch.
