# Terminal UI/UX Redesign

Date: 2026-06-14
Owner: Codex
Scope: `C:\tmp\media\terminal.html` and its existing client-side terminal chrome only
Direction: `Cyber Ops`

## Objective

Redesign the LifeClaw terminal UI into a sharper, more premium, more technical command-center experience without changing the existing terminal workflow, cloudflared behavior, WebSocket/PTTY flow, mobile touch scroll fix, or Claude compatibility.

The result should feel deliberately geeky and operational, not generic glassmorphism.

## Constraints

- Preserve all current terminal functionality.
- Preserve mobile compatibility, including the existing Claude touch-scroll behavior.
- Do not introduce backend changes for this redesign.
- Keep all existing controls available: terminal viewport, key sidebar, prompts panel, sessions panel, markdown panel, pause button, scroll indicator, toast, FAB/sidebar toggle.
- Respect `prefers-reduced-motion`.
- Maintain touch targets appropriate for mobile.

## Design Direction

`Cyber Ops` means a dark tactical console with strong cian accents, precise framing, and subtle diagnostic energy.

Visual pillars:

- Deep black and graphite base instead of soft dark gray.
- Electric cian and ice-blue as the primary signal colors.
- Thin tactical lines, scan grids, corner brackets, and live-status cues.
- Distinct chrome hierarchy: shell frame, command rail, overlays, and utility panels should look like one coherent system.
- The terminal text area remains readable and dominant; chrome must enhance it, not compete with it.

## Proposed Changes

### 1. Global visual system

- Replace the current ambient orb feel with a more technical background:
  - layered dark gradients
  - fine grid or scanline texture
  - restrained cian atmospheric glow
  - subtle radial hotspots near interaction zones
- Define a more opinionated token set in `:root`:
  - background tiers
  - frame/border tiers
  - signal colors
  - stronger mono/sans pairing
  - glow, shadow, and panel tokens

### 2. Terminal shell

- Turn the main terminal container into a tactical frame:
  - stronger outer shell separation from the page background
  - corner accents or brackets
  - internal top highlight and depth
  - more intentional border language
- Improve the xterm viewport presentation:
  - cleaner padding rhythm
  - more integrated scrollbar styling on desktop
  - preserved invisible scrollbar behavior on mobile where needed

### 3. Top identity and situational chrome

- Add a compact top HUD strip above or integrated into the shell:
  - `LifeClaw HyperTerminal`
  - connection/live state
  - session hint or mode label
  - micro signal dots or telemetry labels
- This chrome must remain compact on mobile and denser on desktop.

### 4. Right-side key rail

- Redesign the right sidebar into a command rail:
  - clearer active/inactive states
  - better spacing and icon framing
  - tactical hover/press feedback
  - stronger distinction between dangerous, utility, and navigation controls
- Preserve the current behavior where mobile reveals it with keyboard state.

### 5. Floating utility elements

- Restyle:
  - pause button
  - FAB
  - toast
  - scroll indicator
- All floating elements should share the same Cyber Ops language:
  - compact capsules
  - cian glow edges
  - sharper contrast
  - better motion timing

### 6. Side panels and overlays

- Prompts panel, sessions panel, and markdown panel should feel like tactical drawers:
  - stronger edge definition
  - denser list rows
  - improved headers and separators
  - better contrast for selected/active items
- The markdown panel should read like an analysis surface rather than a generic modal.

### 7. Motion and interaction polish

- Introduce a restrained motion system:
  - shell reveal polish
  - rail hover feedback
  - panel slide timing refinements
  - live status pulse
- Keep motion subtle and technical, not decorative.
- Under reduced motion, eliminate non-essential animation.

## Functional Non-Goals

This redesign does not include:

- changing PTY/WebSocket architecture
- changing server boot behavior
- changing Claude transcript persistence strategy
- adding new backend features
- replacing xterm.js

## Implementation Boundaries

- Primary file expected to change: `C:\tmp\media\terminal.html`
- If needed, very small supporting changes may be made to related startup/asset references, but the redesign should remain primarily self-contained in the terminal page.
- The redesign should be CSS-first with only minimal JS changes when necessary for visual states.

## Verification

Before calling the redesign complete:

- confirm the page still loads
- confirm the terminal still connects
- confirm the mobile touch-scroll path still works with Claude
- confirm the sidebar, sessions, prompts, markdown, toast, pause button, and FAB still appear and behave
- confirm the UI remains usable on mobile and desktop

## Recommendation

Implement the redesign as a full reskin of the existing structure rather than adding new heavy layout systems. That gives the strongest visual jump with the lowest regression risk.
