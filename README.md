# Prunese

Prunese is a native macOS level editor for the side-scrolling routes in *Senator Prune’s Last Miserable Ride*. The editor is written in SwiftUI and AppKit and builds for Apple Silicon.

## Build and open

Requires Apple Silicon, macOS 14 or later, and Xcode or its command line tools with Swift 6.

```sh
./scripts/build-app.sh
open dist/Prunese.app
```

## Design a route

1. Start with the sample or choose **Import Route** and pick a stage from a Washington, American, or Planetary route table.
2. Use the overview strip to jump to another part of the route or **Fit** to see it all at once. Drag platforms and markers on the map. Select a platform to expose its right-edge resize handle. The inspector accepts exact coordinates. Hold Option while dragging to bypass snap, or use the arrow keys to nudge a selection.
3. Add actors, props, and pickups from **Add**. Set the stage slot, material, and hint in **Route**. Save a `.prunese` document for continued editing.
4. Use **Walk Test** to check jumps, moving platforms, and the Moon’s helmet route. Arrow keys or A/D move, Space jumps, Down + Space drops through a ledge, and R restarts. A connected controller with an extended gamepad profile can move and jump.
5. Review the checks in the footer, then choose **Export Route**. Prunese writes one JavaScript override for the selected stage.

## Use a route in the game

The exporter writes `window.PRUNE_WASHINGTON[stage]`, `window.PRUNE_AMERICA[stage]`, or `window.PRUNE_PLANETS[stage]`. In a game build, load the exported script after the corresponding route table and before the platformer initializes. Use a separate override per stage so edits are easy to compare and remove.

The tables cover Stages 2–9, 11–20, and 22–30. The game supplies combat, bosses, room transitions, and campaign behavior. In Deluxe, Stages 2 and 3 take their terrain from the encounter module. Walk Test uses the document’s terrain, so changes to those two stages also need to be checked against the Deluxe encounter layout.

The map uses game coordinates. Ground and ledges store `[left, width, top]`, with optional vertical travel and an access tag on ledges. Enemies store `[x, sprite, attack, patrolY?]`, props `[kind, x]`, and pickups `[kind, x, y]`. A game screen is 1,280 by 720 units.

Stage names and design notes stay in the `.prunese` document. The exported route carries the game’s fields and tuples, including imported settings such as planetary gravity and traction. Import accepts literal route data in JavaScript or JSON.
