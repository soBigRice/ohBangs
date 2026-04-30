# ohBangs Development Rules

## Layout Rules

1. Expanded island content must use rule-based layout.
   Use `HStack`, `VStack`, `Spacer`, `frame(maxWidth:/maxHeight:)`, and shared metrics structs.
   Avoid visual fixes based on ad-hoc `offset`.

2. Spacing and typography must come from shared tokens first.
   Prefer `IslandSpacing`, `IslandTypography`, and layout metrics helpers before introducing new numeric literals.

3. Card layout should be relative to the container.
   Inner padding, inter-card spacing, and column widths should be derived from container size or shared metrics, not hard-coded absolute placement.

4. Prefer `minHeight` or size ranges over fixed heights for content cards.
   Fixed sizes are acceptable only for tiny decorative elements such as dots, strokes, and compact glyph containers.

## Positioning Rules

1. The island window anchor must remain stable.
   Window origin is anchored to the physical notch center when available, otherwise `screen.midX`.
   Adaptive sizing must not change this anchor.

2. The island view must stay top-centered inside the hosting panel.
   The hosting panel may be wider than the collapsed island, so `IslandView` must explicitly occupy the full panel and align its content to the top center.

3. Window sizing and content alignment are separate concerns.
   Do not mix panel resizing logic with collapsed island visual alignment fixes.

## Adaptive Sizing Rules

1. Adaptive behavior should change size, not semantic position.
   Expanding, shrinking, and responsive sizing must preserve the expected center alignment and interaction area.

2. Use metrics helpers for section-specific scaling.
   `ExpandedLayoutMetrics`, `StatusMetrics`, and `CalendarMetrics` should be extended instead of scattering new scaling math in leaf views.

3. Test all three states after layout changes.
   Check `collapsed`, `hint`, and `expanded` states whenever panel size, padding, or alignment changes.

## Change Safety Rules

1. Before changing island positioning, compare with git history.
   Position regressions are subtle and often come from alignment changes rather than obvious coordinate math.

2. After layout edits, always run:
   `XcodeRefreshCodeIssuesInFile` on modified SwiftUI files.
   `BuildProject` for full validation.

3. When fixing regressions, prefer minimal corrective changes first.
   Restore the historical invariant before adding more layout optimization.
