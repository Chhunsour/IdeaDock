# Edge Docking Geometry & Mechanics

IdeaDock introduces an edge-snapping and docking interaction model for macOS desktop spaces. Notes can be tucked away to any of the 8 screen borders or corners.

## Geometry Coordinates

AppKit defines `NSScreen.visibleFrame` with the origin `(0, 0)` at the lower-left corner of the primary display. `EdgeDockGeometry` accounts for arbitrary screen positions, negative display coordinates in multi-monitor setups, and menu bar / Dock insets.

### Available Dock Targets

1. **Top**: Centered along the top visible screen edge.
2. **Bottom**: Centered along the bottom visible screen edge.
3. **Left**: Snapped vertically along the left screen edge.
4. **Right**: Snapped vertically along the right screen edge.
5. **Top-Left Corner**: Snapped at the junction of top and left boundaries.
6. **Top-Right Corner**: Snapped at the junction of top and right boundaries.
7. **Bottom-Left Corner**: Snapped at bottom-left visible corner.
8. **Bottom-Right Corner**: Snapped at bottom-right visible corner.

## Physics & Animation

When dragging near an edge (within a configurable 22 pt threshold), a translucent orange pill preview indicates the snap destination. Upon release, a spring animation glides the window into edge hiding, leaving a compact tab handle that smoothly expands on hover or click.
