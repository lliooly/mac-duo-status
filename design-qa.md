# Design QA: Menu Bar Popover Redesign

## Comparison Target

- Source visual truth: `/var/folders/y4/bnv3n00s26x8tq5q75fb67cr0000gn/T/codex-clipboard-18d5dffc-79f4-48b8-b324-b6ca96127ce8.png`
- Normalized source crop: `docs/design-qa/popover-source-light.png`
- Rendered implementation window: `docs/design-qa/popover-implementation-light-window.png`
- Rendered implementation content: `docs/design-qa/popover-implementation-light.png`
- Side-by-side comparison: `docs/design-qa/popover-comparison-light.png`
- State: light appearance, root page, CPU metric selected, live battery/network/system values.
- Viewport: 340 pt wide SwiftUI window; 340 × 538 px content capture at device scale factor 1.
- Source dimensions: 1456 × 1014 px full reference; light panel crop 530 × 824 px, normalized to 340 × 529 px.
- Implementation dimensions: 340 × 571 px including the temporary debug title bar; normalized content crop 340 × 538 px.

## Full-view Comparison Evidence

The final side-by-side comparison shows the same information order and visual hierarchy: title and settings action, battery summary with progress and power-control action, Wi-Fi summary with network action, segmented system card, and trailing quit action. Card widths, radii, inter-card rhythm, typography hierarchy, blue actions, green status accents, and overall density are materially aligned with the source.

Live values intentionally differ from the mock because the implementation reads the existing real stores. The reference's frosted scenery is also not reproduced as a custom background; the production menu popover uses Apple's official `.glassEffect(.clear, in:)`, while the temporary QA window is shown over its ordinary window background.

## Focused-region Evidence

A separate crop was unnecessary because the 340 px 1:1 content capture keeps the titles, values, action labels, segmented selector, icons, progress track, and status dots legible. The power and Wi-Fi secondary pages were also inspected at the same width in the native preview window:

- Power page: back navigation, active-mode summary, current power source, mode selection, authorization state, and disabled/pending behavior were visible and aligned.
- Wi-Fi page: back navigation, scan action, Wi-Fi toggle, current network selection, categorized network list, hidden-network action, and Settings link were visible and usable.
- The CPU/Thermal/Load selector was exercised and updated both the selected segment and displayed value.

## Required Fidelity Surfaces

- Fonts and typography: system font family matches the macOS target; weights and sizes establish the same title, label, value, and caption hierarchy. Long SSIDs truncate in the middle and action labels remain single-line.
- Spacing and layout rhythm: 16 pt panel padding, 12 pt section gaps, consistent 17 pt card radii, and compact internal spacing closely match the reference. No clipping or overlap was observed on the root or secondary pages.
- Colors and visual tokens: system-adaptive surfaces preserve light/dark behavior; blue actions and green status elements match the reference. Cards are lighter than the outer surface in dark appearance and remain softly separated in light appearance.
- Image quality and asset fidelity: the target contains no raster content requiring generation. All icons use Apple SF Symbols; no custom SVG, CSS-style drawing, placeholder imagery, or external assets were introduced.
- Copy and content: root labels follow the target (`Battery`, `Wi-Fi`, `System`, connected state, controls, and quit). Dynamic values remain sourced from the existing app.
- Accessibility and motion: controls retain labels and identifiers, state is not communicated by color alone, and page/card/selector animations respect Reduce Motion.

## Findings

No actionable P0, P1, or P2 findings remain.

Acceptable differences:

- Dynamic battery, network, power-mode, and CPU values differ from the static reference.
- The source image demonstrates glass over a staged background; the production app delegates that rendering to the system Liquid Glass surface rather than reproducing the backdrop.
- Secondary pages have no supplied visual reference, so they were evaluated for consistency with the approved root-page language rather than pixel matching.

## Comparison History

1. Initial dark rendering: cards were darker than the outer glass and read as heavy black panels; the relative timestamp displayed `Updated in 0 seconds`; the signal area redundantly showed both `3/4` and an icon.
2. Fixes: replaced the card surface with appearance-aware translucent white, introduced localized `just now` copy, and simplified the visible signal indicator to the SF Symbol while retaining `3/4` as its accessibility value.
3. Final light comparison: the root-page hierarchy, spacing, typography, card treatment, colors, icons, and content order align with the source. The root system title was also tightened from `System Health` to `System` to match the target.

## Implementation Checklist

- Root summary cards match the selected design direction.
- Official `.glassEffect(.clear, in:)` is limited to the outer panel on macOS 26 and newer.
- Older macOS versions retain the native material fallback.
- Power, Wi-Fi, and credential pages use the shared card and header language.
- Navigation, selector, progress, and entrance animations respect Reduce Motion.
- Existing stores, coordinators, providers, helper protocols, and backend behavior are unchanged by this redesign.

## Follow-up Polish

- P3: inspect on additional physical displays to account for wallpaper-dependent Liquid Glass tinting.

final result: passed
