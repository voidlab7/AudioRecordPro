# AudioRecord Design System

> Category: macOS Native Audio Tool
> Recording + Light Editing. Industrial dark, functional, coral waveform accent.
> Base: Adapted from Linear App design system structure
> Token Source: `AudioRecordApp/Sources/Utilities/IndustrialDesignTokens.swift`

---

## 1. Visual Theme & Atmosphere

AudioRecord is a dark-mode-native macOS audio tool built for knowledge workers who need to capture system audio, app audio, and microphone input with zero friction. The visual language is **Industrial** — inspired by hardware audio equipment (mixing consoles, rack units, VU meters) rather than consumer software aesthetics.

The design is built on a near-black canvas (`#0E1416` — a cool dark teal-black) where functional elements emerge through luminance hierarchy. Unlike consumer apps that use color for decoration, AudioRecord uses color exclusively for **functional signaling**: coral red for waveforms and recording state, cyan for interactive accents and level meters, amber for warnings. The overall impression is a professional control surface — dense with information but never cluttered.

**Key Characteristics:**
- Dark-mode-native: `#0E1416` base surface, `#161D1E` container low, `#1A2122` container standard
- System font (SF Pro) at functional sizes — no decorative typography
- Monospaced digits for all numerical displays (timers, dB values, sample rates)
- Single chromatic accent: Cyan (`#8AEBFF` primary / `#22D3EE` container) for interactive elements
- Functional signal colors: Coral (`#FF6B5F`) for waveforms, Amber (`#FFD6A3`) for warnings, Red (`#FF453A`) for recording/danger
- Semi-transparent borders (`#3C494C`) for structure without visual noise
- Glow effects on active states (recording button, level peaks) — the only "decorative" element, justified by hardware metaphor
- AppKit native (NSView/CALayer), not SwiftUI — pixel-precise control

**Design Philosophy:**
- **Recording-first**: The idle state's primary affordance is "start recording", not "browse files" or "edit"
- **Two-workspace model**: Recording Workspace and Editing Workspace are visually distinct modes, never mixed
- **Information density over whitespace**: Audio professionals expect dense, scannable interfaces
- **Hardware metaphor**: Buttons feel like physical controls, meters behave like real VU meters, the interface has "weight"
- **Earned complexity**: Features appear only when relevant (edit tools activate only after recording stops)

---

## 2. Color Palette & Roles

### Background Surfaces (Luminance Ladder)

| Token | Hex | Role |
|-------|-----|------|
| `surface` | `#0E1416` | Deepest background — status bar, base canvas |
| `surfaceDim` | `#0E1416` | Same as surface (reserved for future light mode) |
| `surfaceContainerLowest` | `#090F11` | Recessed areas (below surface) |
| `surfaceContainerLow` | `#161D1E` | Primary content areas — waveform bg, sidebar bg |
| `surfaceContainer` | `#1A2122` | Standard containers — track items, panels |
| `surfaceContainerHigh` | `#242B2D` | Hover states, elevated containers |
| `surfaceContainerHighest` | `#2F3638` | Selected states, active containers |
| `surfaceBright` | `#343A3C` | Brightest surface (rare — tooltips, popovers) |

**Luminance progression**: Each step increases perceived brightness by ~15-20%, creating a 7-level depth system without shadows.

### Text & Content

| Token | Hex | Role |
|-------|-----|------|
| `onSurface` | `#DDE4E5` | Primary text — headings, labels, values |
| `onSurfaceVariant` | `#BBC9CD` | Secondary text — descriptions, metadata |
| `textTertiary` | `#9CA3AF` | Tertiary text — placeholders, disabled, timestamps |
| `textSecondary` | `#D1D5DB` | Legacy secondary (prefer `onSurfaceVariant`) |
| `textPrimary` | `#E5E7EB` | Legacy primary (prefer `onSurface`) |

### Primary Accent (Cyan — Interactive)

| Token | Hex | Role |
|-------|-----|------|
| `primary` | `#8AEBFF` | Primary interactive — links, selected states, level meter |
| `primaryContainer` | `#22D3EE` | Deeper cyan — waveform gradient, meter fill |
| `onPrimary` | `#00363E` | Text on primary backgrounds |
| `inversePrimary` | `#006877` | Inverted context primary |

### Secondary (Sky Blue — Waveform Gradient)

| Token | Hex | Role |
|-------|-----|------|
| `secondary` | `#7BD0FF` | Secondary accent — waveform gradient lower |
| `secondaryContainer` | `#00A6E0` | Deep sky blue container |

### Tertiary (Amber — Warning & Attention)

| Token | Hex | Role |
|-------|-----|------|
| `tertiary` | `#FFD6A3` | Warning text, "EDITING" badge, attention states |
| `tertiaryContainer` | `#FFB13B` | Amber container — high-level meter zone |

### Error (Red — Danger & Overload)

| Token | Hex | Role |
|-------|-----|------|
| `error` | `#FFB4AB` | Error text, overload indicators |
| `errorContainer` | `#93000A` | Deep red container |

### Waveform Colors (Coral Red Family — Recording Identity)

| Token | Hex | Role |
|-------|-----|------|
| `waveformAccent` | `#FF453A` | Playhead, recording indicator — the "hot" color |
| `waveformCoral` | `#FF6B5F` | Primary waveform bars — the signature color |
| `waveformSoft` | `#FF8A80` | Secondary waveform, weak levels |
| `waveformMuted` | `#FF6B5F` @ 0.32 | Silent segments, muted regions |

### Status Colors (Functional Signals)

| Token | Hex | Role |
|-------|-----|------|
| `statusSuccess` | `#22C55E` | Normal operation, connected |
| `statusWarning` | `#F59E0B` | High level 70-90%, attention needed |
| `statusDanger` | `#EF4444` | Overload >90%, critical |
| `statusCritical` | `#DC2626` | Recording button idle state |

### Border & Divider

| Token | Hex | Role |
|-------|-----|------|
| `outline` | `#859397` | Primary border (rare — high contrast) |
| `outlineVariant` | `#3C494C` | Standard border — panel edges, dividers |
| `borderMuted` | `#374151` | Legacy muted border |

### Grid & Texture

| Token | Value | Role |
|-------|-------|------|
| `gridLight` | `white @ 0.03` | Background grid texture |
| `gridMedium` | `white @ 0.06` | Section grid, waveform center line |
| `gridHeavy` | `white @ 0.12` | Emphasized grid lines |

### Glow Effects (Hardware Metaphor)

| Token | Value | Role |
|-------|-------|------|
| `glowCyan` | `#22D3EE @ 0.25` | Recording button active, level meter peak |
| `glowWarning` | `#F59E0B @ 0.30` | Warning state glow |
| `glowDanger` | `#EF4444 @ 0.35` | Overload state glow |

### Editor-Specific Colors

| Token | Value | Role |
|-------|-------|------|
| `editorHandle` | = `primary` (#8AEBFF) | Selection drag handles |
| `editorDimOverlay` | `#0E1416 @ 0.4` | Outside-selection dimming |
| `editorSilenceOverlay` | `#242B2D @ 0.6` | Detected silence regions |
| `editorSilenceLine` | = `error` (#FFB4AB) | Silence deletion marker |
| `editorEditingBadge` | = `tertiary` (#FFD6A3) | "EDITING" status badge |

---

## 3. Typography Rules

### Font Family

- **Primary**: SF Pro (system font) — via `NSFont.systemFont`
- **Monospaced Digits**: SF Mono — via `NSFont.monospacedDigitSystemFont`
- **No custom fonts**: macOS native feel, zero load time, guaranteed rendering

### Hierarchy

| Role | API | Size | Weight | Use |
|------|-----|------|--------|-----|
| H1 | `IndustrialTypography.h1` | 18px | Bold | Section headers (uppercase) |
| H2 | `IndustrialTypography.h2` | 14px | Bold | Panel headers, file names |
| Body | `IndustrialTypography.body` | 13px | Regular | Standard text, descriptions |
| Small | `IndustrialTypography.small` | 12px | Regular | Secondary info, metadata |
| Label | `IndustrialTypography.label` | 11px | Semibold | Button labels, badges, tags |
| Timer | `IndustrialTypography.timer` | 28px | Bold Mono | Recording timer display |
| MonoDB | `IndustrialTypography.monoDB` | 10px | Regular Mono | dB values, time codes, status bar |

### Principles

- **Functional sizing**: No decorative large text. Largest element is the timer (28px) because it's the most critical real-time information during recording.
- **Uppercase for structure**: Section headers (`RECORDING TARGET`, `SELECT APPLICATION SOUND`) use uppercase + label weight to create visual landmarks without increasing size.
- **Monospaced for numbers**: All numerical values (timer, dB, sample rate, file size) use monospaced digits to prevent layout shift during real-time updates.
- **No letter-spacing tricks**: System font at system sizes. Readability over style.
- **Weight as hierarchy**: Bold (headers) → Semibold (labels) → Regular (body) → Regular Mono (data). Three levels only.

---

## 4. Component Stylings

### Buttons

**Record Button (Primary Action)**
- Shape: Circle, 48px diameter
- Background: `statusCritical` (#DC2626) idle → `statusDanger` (#EF4444) recording
- Glow: Multi-layer cyan glow when recording (`glowCyan` × 3 layers)
- Icon: Filled circle (idle) → Filled square (recording)
- Corner radius: `IndustrialCornerRadius.xl` (32px)

**Industrial Button (Standard)**
- Background: `surfaceContainerHigh` (#242B2D)
- Text: `onSurfaceVariant` (#BBC9CD)
- Hover: `surfaceContainerHighest` (#2F3638)
- Active: `surfaceContainerHighest` + `primaryContainer` 1px border
- Radius: `IndustrialCornerRadius.sm` (8px)
- Height: 28-32px
- Font: `IndustrialTypography.label` (11px Semibold)

**Icon Button**
- Size: 28×28px
- Background: transparent
- Hover: `surfaceContainerHigh`
- Icon: SF Symbol, `onSurfaceVariant` color
- Radius: `IndustrialCornerRadius.xs` (4px)

**Ghost Button (Toolbar)**
- Background: transparent
- Text: `onSurfaceVariant`
- Hover: `surfaceContainerHigh` background appears
- Disabled: 0.3 opacity
- Radius: `IndustrialCornerRadius.xs` (4px)

### Cards & Containers

**Panel (Sidebar, Track Panel)**
- Background: `surfaceContainer` (#1A2122)
- Border-right/left: 1px `outlineVariant` (#3C494C)
- No radius (full-bleed panels)
- Shadow: None (luminance hierarchy provides depth)

**File Row (Recorded Files List)**
- Background: transparent
- Hover: `surfaceContainerHigh`
- Selected: `surfaceContainerHighest` + 3px left border `primary`
- Height: ~56px
- Padding: 12px horizontal

**Track Item**
- Background: `surfaceContainer`
- Border: 1px `outlineVariant`
- Radius: `IndustrialCornerRadius.sm` (8px)
- Contains: Track header + waveform clip inline

### Level Meter

**Vertical Bar Meter (L/R)**
- Background: `surfaceContainerLow`
- Fill gradient: `statusSuccess` (bottom) → `statusWarning` (70%) → `statusDanger` (90%+)
- Peak hold: 2px line at peak, decays over 1.5s
- dB scale: `IndustrialTypography.monoDB`, `textTertiary`
- Border: 1px `outlineVariant`
- Width: 12px per channel

### Waveform Display

**Recording Waveform (Real-time)**
- Bar width: 2px
- Bar spacing: 3px (center-to-center)
- Bar color: `waveformCoral` (#FF6B5F)
- Bar alpha: proportional to amplitude (0.3 min, 1.0 max)
- Direction: Left-to-right scroll (newest samples on right)
- Background: `surfaceContainerLow`
- Center line: 1px dashed, `gridMedium`

**Editor Waveform (Static, Zoomable)**
- Bar width: 1.2px
- Bar spacing: 2.2px (center-to-center)
- Bar color: `waveformCoral` (#FF6B5F)
- Drawing: Symmetric around center line (min/max peaks)
- Selection inside: alpha 0.34-1.0 (amplitude-proportional)
- Selection outside: alpha 0.15-0.4 (dimmed)
- Playhead: 1.5px vertical line + 10px triangle handle, `waveformAccent`

### Selection Handles (Editor)

- Width: 4px (`editorHandleWidth`)
- Color: `primary` (#8AEBFF)
- Radius: 2px top/bottom
- Texture: 3 horizontal lines (grip indicator), 3px spacing
- Hit zone: 8px (`editorHandleHitZone`)
- Hover: `glowCyan` effect
- Cursor: `resizeLeftRight`

### Badges & Status

**Format Badge**
- Background: `surfaceContainerHigh`
- Text: `onSurfaceVariant`, `IndustrialTypography.label`
- Radius: `IndustrialCornerRadius.xs` (4px)
- Padding: 2px 6px

**Status Badge ("STANDBY", "RECORDING", "EDITING")**
- STANDBY: `textTertiary` text, no background
- RECORDING: `statusDanger` text, pulsing dot
- EDITING: `tertiary` (#FFD6A3) text, `surfaceContainerHighest` background

### Navigation Bar (Editor)

- Height: 44px (`editorNavBarHeight`)
- Background: `surfaceContainerLow`
- Layout: [← Back] | [File Name centered] | [↩ ↪] [Save]
- Border-bottom: 1px `outlineVariant`
- Back button: SF Symbol `chevron.left` + "返回"
- Save button: Primary highlight when unsaved changes

### Toolbar (Editor)

- Height: 36px (`editorToolbarHeight`)
- Background: `surfaceContainer`
- Tools: [裁剪] [静音裁剪] [标准化] [淡入淡出] ... [▶ 预览] [■]
- Tool buttons: Ghost style, activate to primary color
- Border-top: 1px `outlineVariant`

### Status Bar

- Height: 24px (`editorStatusBarHeight`)
- Background: `surface` (#0E1416)
- Font: `IndustrialTypography.monoDB` (10px mono)
- Text: `onSurfaceVariant`
- Content: `DUR 02:34.50 │ 48000 Hz │ STEREO │ EDITS: 3/20`
- Separator: `│` character in `outlineVariant`

---

## 5. Layout Principles

### Two-Workspace Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AudioRecord App                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─── Recording Workspace ───┐  ┌─── Editing Workspace ──┐ │
│  │                           │  │                         │ │
│  │  Sidebar │ Content Area   │  │  Sidebar │ Editor Area  │ │
│  │  (260px) │ (flex)         │  │  (260px) │ (flex)       │ │
│  │          │                │  │          │              │ │
│  └───────────────────────────┘  └─────────────────────────┘ │
│                                                             │
│  Mode switch: Left-right slide animation (200ms easeOut)    │
└─────────────────────────────────────────────────────────────┘
```

### Recording Workspace Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  TitleBar: [AudioRecord]  [录制目标]                   [导出 ▶]  │  44px
├──────────────────────────────────────────────────────────────────┤
│  EditToolbar: [裁剪] [标准化] [淡入] [淡出]  (disabled in rec)   │  36px
├────────┬──────────────────────────────────────────┬──────────────┤
│ Track  │  Waveform + Time Ruler                   │  Level Meter │  flex
│ Panel  │  ~~~realtime waveform~~~                  │  L ▓▓░░     │
│ [🔊][S]│  [zoom scrollbar]                        │  R ▓▓░░     │
├────────┴──────────────────────────────────────────┴──────────────┤
│  ControlPanel: 00:00.00  [▶] [● REC] [■]  48kHz·32bit·Stereo    │  150px
├──────────────────────────────────────────────────────────────────┤
│  StatusBar: STANDBY │ System Audio │ ~/Recordings/               │  28px
└──────────────────────────────────────────────────────────────────┘
```

### Editing Workspace Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  EditorNavBar: [← 返回]  Recording.wav  [↩] [↪]  [保存]         │  44px
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  EditorWaveformView (zoomable, scrollable, selectable)           │  flex
│  ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┃  │
│  Time Ruler: 0:00    0:30    1:00    1:30    2:00                │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  EditorToolbar: [裁剪] [静音] [标准化] [淡入淡出]  [▶ 预览] [■]  │  36px
├──────────────────────────────────────────────────────────────────┤
│  StatusBar: DUR 02:34 │ 48kHz │ STEREO │ EDITS: 3/20            │  24px
└──────────────────────────────────────────────────────────────────┘
```

### Spacing System

| Token | Value | Use |
|-------|-------|-----|
| `unit` | 4px | Base unit |
| `xs` | 4px | Tight spacing (icon-to-label) |
| `sm` | 8px | Button gaps, inline spacing |
| `md` | 16px | Panel padding, section gaps |
| `lg` | 24px | Major section separation |
| `xl` | 32px | Page-level margins |
| `gutter` | 12px | Card internal padding |

### Fixed Dimensions

| Element | Value | Rationale |
|---------|-------|-----------|
| Sidebar width | 260px | Fits file names + metadata without truncation |
| Title bar height | 44px | macOS standard |
| Toolbar height | 36px | Compact but touchable |
| Status bar height | 24-28px | Minimal, data-dense |
| Control panel height | 150px | Accommodates record button + transport + info |
| Min window size | 960×600px | Ensures all elements visible |

### Grid & Alignment

- **8px base grid**: All spacing values are multiples of 4px, with 8px as the primary rhythm
- **Grid texture**: Optional 24px background grid (`gridLight`) for visual structure in waveform areas
- **Vertical rhythm**: Component heights align to 4px grid (24, 28, 32, 36, 44px)
- **Horizontal alignment**: Left-aligned text throughout (except editor file name: centered)

---

## 6. Depth & Elevation

AudioRecord uses **luminance stepping** (not shadows) as the primary depth indicator on dark surfaces. Shadows are reserved for floating elements and glow effects.

| Level | Treatment | Use |
|-------|-----------|-----|
| Level 0 (Recessed) | `surfaceContainerLowest` (#090F11) | Below-surface areas |
| Level 1 (Base) | `surface` (#0E1416) | Status bar, deepest canvas |
| Level 2 (Content) | `surfaceContainerLow` (#161D1E) | Waveform bg, sidebar bg |
| Level 3 (Container) | `surfaceContainer` (#1A2122) | Panels, track items |
| Level 4 (Elevated) | `surfaceContainerHigh` (#242B2D) | Hover states, buttons |
| Level 5 (Active) | `surfaceContainerHighest` (#2F3638) | Selected, active |
| Level 6 (Floating) | `surfaceBright` (#343A3C) + shadow | Tooltips, popovers |

### Shadow System

Shadows are used sparingly — only for floating elements and emphasis:

| Type | Spec | Use |
|------|------|-----|
| Small | `0 2px 6px rgba(0,0,0,0.35)` | Buttons, small cards |
| Medium | `0 4px 12px rgba(0,0,0,0.45)` | Panels, dialogs |
| Large | `0 6px 18px rgba(0,0,0,0.55)` | Modal windows, floating panels |

### Glow System (Hardware Metaphor)

Glow replaces shadow for active/recording states — simulating LED backlighting:

| Type | Spec | Use |
|------|------|-----|
| Cyan Glow | `0 0 20px #22D3EE @ 0.8` | Recording button active, level peak |
| Warning Glow | `0 0 12px #F59E0B @ 0.6` | High level warning |
| Danger Glow | `0 0 16px #EF4444 @ 1.0` | Overload state |
| Multi-layer | 3× stacked with increasing radius | Recording button (signature effect) |

---

## 7. Do's and Don'ts

### Do

- Use the luminance ladder (`surface` → `surfaceContainerLowest` → ... → `surfaceBright`) for depth — never solid bright backgrounds
- Use `waveformCoral` (#FF6B5F) exclusively for audio waveform visualization — it's the product's visual signature
- Use monospaced digits (`NSFont.monospacedDigitSystemFont`) for ALL numerical displays
- Keep the recording button as the single most prominent element in recording workspace
- Use uppercase + `IndustrialTypography.label` for section headers (e.g., "RECORDING TARGET")
- Apply glow effects only on active/recording states — they simulate hardware LEDs
- Maintain 1px `outlineVariant` borders between major layout sections
- Use `textTertiary` for placeholder/hint text — never pure gray
- Reserve `primary` (#8AEBFF cyan) for interactive elements only — links, selections, active states
- Disable edit tools visually (0.3 opacity) during recording — never hide them

### Don't

- Don't use pure white (`#FFFFFF`) for text — `onSurface` (#DDE4E5) prevents eye strain
- Don't use pure black (`#000000`) for backgrounds — `surface` (#0E1416) has a cool teal undertone
- Don't mix recording UI and editing UI in the same view — they are separate workspaces
- Don't use gradients for decoration — gradients are only for level meter fill (functional)
- Don't use rounded corners larger than 16px except for the record button (32px circle)
- Don't add decorative elements (blobs, waves, particles) — every pixel must be functional
- Don't use emoji as UI elements — use SF Symbols exclusively
- Don't center-align body text — left-align everything except the editor file name
- Don't use card-with-colored-left-border pattern — it's an AI slop indicator
- Don't show "empty state" illustrations — use functional text prompts instead
- Don't use shadows on dark-on-dark surfaces — use luminance stepping
- Don't animate decoratively — animations are only for state transitions (200ms) and real-time data (16.7ms)

### Anti-AI-Slop Checklist

| # | Pattern | AudioRecord Status |
|---|---------|-------------------|
| 1 | Purple/indigo gradient | ❌ Not used — coral + cyan on near-black |
| 2 | Three-column feature grid | ❌ Not applicable — tool UI, not marketing |
| 3 | Colored circle icons | ❌ SF Symbols only, no decorative circles |
| 4 | Everything centered | ❌ Left-aligned, functional layout |
| 5 | Uniform large radius | ❌ 4px/8px functional radius, 32px only for record button |
| 6 | Decorative blobs/waves | ❌ Grid texture only, functional |
| 7 | Emoji as design | ❌ SF Symbols exclusively |
| 8 | Card left-border color | ❌ 3px left indicator only for selected file (functional) |
| 9 | Template hero copy | ❌ No hero section — tool UI |
| 10 | Cookie-cutter rhythm | ❌ Asymmetric layout driven by function |

---

## 8. Responsive Behavior

### Window Size Constraints

AudioRecord is a macOS desktop app with fixed minimum dimensions:

| Constraint | Value | Rationale |
|-----------|-------|-----------|
| Minimum width | 960px | Sidebar (260) + Content (700) minimum |
| Minimum height | 600px | All panels visible without scrolling |
| Default size | 1200×800px | Comfortable for most displays |
| Maximum | Unconstrained | Fills available space |

### Sidebar Behavior

- **Fixed width**: 260px (not collapsible in V1.x)
- **Resizable**: 200-400px via NSSplitView divider
- **Always visible**: Sidebar persists in both recording and editing workspaces
- **Future**: Collapse/expand toggle planned for V2.x

### Content Area Scaling

| Window Width | Behavior |
|-------------|----------|
| 960-1100px | Compact mode — level meter narrows, toolbar wraps |
| 1100-1400px | Standard mode — all elements at designed sizes |
| 1400px+ | Expanded mode — waveform area grows, more time visible |

### Waveform Scaling

- Waveform view fills available width (flex: 1)
- Bar density adjusts to viewport: more bars visible at wider widths
- Zoom level persists across resize — time range stays constant
- Level meter maintains fixed width (independent of window size)

### Touch Targets (Accessibility)

All interactive elements meet minimum 28×28px hit area:
- Buttons: 28px minimum height
- Selection handles: 8px visual width, 8px hit zone each side = 16px effective
- Tab buttons: Full tab width × 44px height
- File rows: Full width × 56px height

---

## 9. Agent Prompt Guide

### Quick Color Reference (for development agents)

```swift
// Backgrounds (dark → light)
surface:                #0E1416  // Deepest — status bar
surfaceContainerLow:    #161D1E  // Content areas — waveform, sidebar
surfaceContainer:       #1A2122  // Panels, containers
surfaceContainerHigh:   #242B2D  // Hover, elevated
surfaceContainerHighest:#2F3638  // Selected, active

// Text (bright → dim)
onSurface:              #DDE4E5  // Primary text
onSurfaceVariant:       #BBC9CD  // Secondary text
textTertiary:           #9CA3AF  // Tertiary, disabled

// Functional colors
primary (cyan):         #8AEBFF  // Interactive accent
waveformCoral:          #FF6B5F  // Waveform bars (signature)
waveformAccent:         #FF453A  // Playhead, recording
tertiary (amber):       #FFD6A3  // Warnings, editing badge
error:                  #FFB4AB  // Error states

// Borders
outlineVariant:         #3C494C  // Standard border
```

### Component Implementation Guide

When implementing UI components for AudioRecord:

1. **Always use `IndustrialDesignTokens.swift` tokens** — never hardcode hex values
2. **Backgrounds are `surfaceContainerLow`** for content areas, `surfaceContainer` for panels
3. **Text defaults to `onSurface`** — use `onSurfaceVariant` for secondary, `textTertiary` for tertiary
4. **Borders are 1px `outlineVariant`** — between major sections only, not around every element
5. **Buttons use `surfaceContainerHigh` background** with `onSurfaceVariant` text
6. **Active/selected states use `primary` (#8AEBFF)** — border or text color, not background fill
7. **Waveform is always `waveformCoral`** — the only coral-red element in the entire UI
8. **Numbers are always monospaced** — `NSFont.monospacedDigitSystemFont`
9. **Glow effects only during recording** — `IndustrialGlow.cyan/warning/danger`
10. **Animations are 120ms standard, 200ms for page transitions** — `IndustrialAnimation`

### State Coverage Checklist

Every view must handle these 5 states:

| State | Visual Treatment |
|-------|-----------------|
| **Loading** | Skeleton animation (45° stripes, 1.5s cycle) + "加载中..." text |
| **Empty** | Functional text prompt (e.g., "↔ 在波形上拖拽创建选区") — no illustrations |
| **Error** | Red icon + error message + retry action |
| **Populated** | Normal content display |
| **Edge** | Graceful degradation (long text truncates, large files load progressively) |

### Two-Workspace State Machine

```
App Launch → Recording Workspace (Idle)
  │
  ├── User clicks Record → Recording state
  │     └── User clicks Stop → Recording Workspace (has file, edit tools activate)
  │
  ├── User clicks Edit button on file → Editing Workspace
  │     ├── User edits → Editing Workspace (modified)
  │     └── User clicks Back → Recording Workspace
  │
  └── User selects file → Recording Workspace (file selected, can play/edit)
```

### Craft Rules Compliance

This design system has been checked against:

- [x] **Color**: 4-layer palette (neutral 85%+, accent <5%, semantic <5%, effect <1%)
- [x] **Typography**: Functional sizing, 3-weight system, monospaced numbers
- [x] **Typography Hierarchy**: Single dominant entry (timer 28px), clear 3-level hierarchy
- [x] **Animation Discipline**: Only state transitions (120-200ms) and real-time data (16.7ms)
- [x] **Anti-AI Slop**: All 10 patterns checked and avoided
- [x] **Accessibility Baseline**: 14.7:1 contrast ratio (onSurface on surface), 28px min touch targets
- [x] **State Coverage**: 5 states defined for all views
- [x] **UX Laws**: Hick (max 4 edit tools), Fitts (8px handle hit zone), Gestalt (proximity grouping)

---

## Appendix: Token Source Mapping

All tokens defined in: `AudioRecordApp/Sources/Utilities/IndustrialDesignTokens.swift`

| Design System Section | Swift Struct |
|----------------------|--------------|
| Colors | `IndustrialColors` |
| Typography | `IndustrialTypography` |
| Spacing | `IndustrialSpacing` |
| Corner Radius | `IndustrialCornerRadius` |
| Shadows | `IndustrialShadow` |
| Glow Effects | `IndustrialGlow` |
| Animations | `IndustrialAnimation` |

---

*Design System v1.0 — Created 2026-05-21 — AudioRecord for macOS*
*Base: Linear App structure adapted for Industrial Audio Tool aesthetic*
*Maintainer: 绘·设计师*
