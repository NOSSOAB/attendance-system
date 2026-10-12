---
name: HUCE SA Mobile Design System
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#434656'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#737688'
  outline-variant: '#c3c5d9'
  surface-tint: '#004fe5'
  primary: '#0047cf'
  on-primary: '#ffffff'
  primary-container: '#165dff'
  on-primary-container: '#eeefff'
  inverse-primary: '#b6c4ff'
  secondary: '#465d94'
  on-secondary: '#ffffff'
  secondary-container: '#a9c0fd'
  on-secondary-container: '#364d83'
  tertiary: '#006312'
  on-tertiary: '#ffffff'
  tertiary-container: '#007f1a'
  on-tertiary-container: '#c6ffba'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dce1ff'
  primary-fixed-dim: '#b6c4ff'
  on-primary-fixed: '#00164f'
  on-primary-fixed-variant: '#003bb0'
  secondary-fixed: '#d9e2ff'
  secondary-fixed-dim: '#b0c6ff'
  on-secondary-fixed: '#001945'
  on-secondary-fixed-variant: '#2d457a'
  tertiary-fixed: '#72ff70'
  tertiary-fixed-dim: '#4ee253'
  on-tertiary-fixed: '#002203'
  on-tertiary-fixed-variant: '#00530e'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Be Vietnam Pro
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Be Vietnam Pro
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  title-md:
    fontFamily: Be Vietnam Pro
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: '0'
  body-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
    letterSpacing: '0'
  body-md:
    fontFamily: Be Vietnam Pro
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: '0'
  body-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: '0'
  label-md:
    fontFamily: Be Vietnam Pro
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.02em
  caption:
    fontFamily: Be Vietnam Pro
    fontSize: 10px
    fontWeight: '500'
    lineHeight: 12px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.25rem
---

## Brand & Style

This design system establishes the visual and structural language for the official mobile experience of Hanoi University of Civil Engineering (HUCE). Built for high-volume academic interactions, it serves students, faculty, and administrative staff who require immediate clarity, swift task execution, and modern institutional trust.

The aesthetic fuses **Corporate/Modern** structural rigor with **Contemporary Clean Minimalism**. The tone is authoritative yet youthful, academic yet streamlined, replacing legacy bureaucratic interfaces with crisp visual hierarchy, breathing room, and soft architectural surfaces. 

Key product principles:
- **Clarity under pressure:** Immediate comprehension of critical academic schedules, attendance status, and alerts within sub-second visual scanning.
- **Architectural precision:** Crisp geometric layouts, disciplined rhythm, and soft structural frames referencing modern engineering blueprints.
- **Approachable authority:** Balancing the institutional prestige of HUCE with engaging, modern digital interactions.

## Colors

The palette balances institutional integrity with crisp utility:

- **Primary (`#165DFF`):** The signature vibrant brand blue. Used for prominent interactive elements, active navigation states, primary buttons, and key progress metrics.
- **Secondary (`#0E2A5E`):** A deep academic navy. Anchors high-emphasis headers, prominent text labels, and formal institutional accents.
- **Tertiary (`#00B42A`):** Pure semantic success emerald green. Deployed for confirmed attendance, completed course units, and positive status badges.
- **Neutral Surface (`#F8FAFC`):** Slate 50 background canvas delivering an airy, soft-contrast workspace that eliminates eye fatigue.
- **Card Base (`#FFFFFF`):** High-purity white surfaces set directly against `#F8FAFC` to create natural depth without visual noise.
- **Status Accent Amber (`#FF7D00` / `#D97706`):** Dedicated to warnings, pending attendance, schedule adjustments, or upcoming deadlines.
- **Status Accent Azure (`#0EA5E9` / `#E0F2FE`):** Soft contextual informational badges for upcoming sessions and lecture tags.
- **Border Neutral (`#F1F5F9`):** Slate-100 hairline separator lines maintaining structural form without adding clutter.

## Typography

Typography is set entirely in **Be Vietnam Pro**, engineered specifically to optimize tone, clarity, and accent markings across Vietnamese diacritics while rendering English technical nomenclature cleanly.

- **Weight Discipline:** Restrict styling to Regular (400) for body and descriptive subtext, Medium (500) for interactive labels and inputs, and Semi-Bold/Bold (600/700) for headlines, active tab states, and numerical telemetry (student IDs, classroom numbers, GPA).
- **Diacritical Protection:** Increased line heights prevent stacked Vietnamese tone marks (e.g., dấu hỏi, ngã, nặng) from clipping or overlapping adjacent card boundaries and input fields.
- **Hierarchy:** Course codes, lecture hall coordinates, and dates are prioritized through weight shifts (600) rather than disproportionate font sizing.

## Layout & Spacing

The mobile layout employs a fluid single-column model strictly tuned for touch ergonomics:

- **Horizontal Canvas Margin:** Fixed `1rem` (16px) margins on mobile viewports prevent edge crowding while maximizing content width for schedules and tables.
- **Vertical Flow:** Standard element spacing relies on an 8-point rhythmic grid with a 4-point micro-step: `0.5rem` (8px) between related label-input groups, `0.75rem` (12px) between sub-elements inside cards, and `1rem` (16px) between card modules.
- **Bottom Clearance:** A persistent padding of `5.5rem` (88px) is applied to all scrollable views to prevent the fixed bottom navigation bar from occluding primary content or bottom-anchored actions.
- **Safe Areas:** Adheres to hardware safe areas at top (notch / dynamic island) and bottom (home indicator) edges.

## Elevation & Depth

Visual hierarchy is established using quiet tonal separation paired with soft ambient diffusion:

- **Elevation 0 (Canvas Base):** Surface color `#F8FAFC`. Zero elevation.
- **Elevation 1 (Cards & Modules):** Pure white background (`#FFFFFF`) supported by a structural hairline border `border border-slate-100` (`#F1F5F9`) and a soft ambient shadow `box-shadow: 0 1px 3px 0 rgba(15, 23, 42, 0.05), 0 1px 2px -1px rgba(15, 23, 42, 0.04)`.
- **Elevation 2 (Floating Action & Bottom Bar):** Background `#FFFFFF` with boundary border `#F1F5F9` and upward elevation `box-shadow: 0 -4px 12px -2px rgba(15, 23, 42, 0.04), 0 -2px 4px -2px rgba(15, 23, 42, 0.02)`.
- **Elevation 3 (Modals & Action Sheets):** `#FFFFFF` surface with deep backdrop blur (`backdrop-filter: blur(8px)`) on overlay `#0F172A` at 40% opacity, paired with downward soft drop shadow `0 20px 25px -5px rgba(15, 23, 42, 0.1)`.

## Shapes

The design uses balanced, rounded geometry calibrated between 16px and 20px to create a friendly, approachable touch surface:

- **Standard Cards:** `16px` (`rounded-2xl`) to `20px` corner radii, ensuring cards feel self-contained and comfortable to tap.
- **Buttons & Input Fields:** `12px` to `14px` border radius, balancing tactile friendliness with clean structure.
- **Status Badges & Pills:** Full pill radius (`9999px`) to immediately distinguish categorical indicators from actionable rectangular cards.
- **Bottom Navigation Shell:** Top corners rounded at `20px` (`rounded-t-[20px]`) to establish seamless continuity with resting content cards.

## Components

### 1. Cards
- **Base Style:** Background `#FFFFFF`, border `1px solid #F1F5F9`, border-radius `16px` or `20px`, shadow `shadow-sm`.
- **Padding:** `1rem` (16px) or `1.25rem` (20px) internal breathing room.
- **Variants:** 
  - *Schedule Card:* Displays course title (16px Semi-Bold), room badge (e.g., "P.302-H1"), instructor, and time block with a 4px left-border accent in `#165DFF`.
  - *Profile Card:* Displays student avatar (56px circle with 2px `#165DFF` rim), full student name, ID (`MSSV`), class code, and verified badge.

### 2. Status Badges & Chips
- **Design Rule:** 100% full pill (`rounded-full`), padding `4px 10px`, font size `11px` to `12px` with weight `600`.
- **Success (Present / Đã điểm danh):** Background `#ECFDF5`, text `#059669`, border `1px solid #A7F3D0`.
- **Warning (Pending / Chờ điểm danh / Cảnh báo vắng):** Background `#FFFBEB`, text `#D97706`, border `1px solid #FDE68A`.
- **Info (Scheduled / Đang diễn ra):** Background `#EFF6FF`, text `#165DFF`, border `1px solid #BFDBFE`.
- **Neutral (Excused / Có phép):** Background `#F1F5F9`, text `#475569`, border `1px solid #E2E8F0`.

### 3. Bottom Navigation Bar
- **Configuration:** Fixed bottom bar, 4 items:
  1. *Trang chủ* (Icon: Home/Dashboard)
  2. *Lịch học* (Icon: Calendar/Schedule)
  3. *Điểm danh* (Icon: QR/Checklist)
  4. *Hồ sơ* (Icon: User/Profile)
- **Active State (Default: Hồ sơ):** Icon and label tinted `#165DFF`. Top or bottom indicator pill or subtle active pill highlight in `#EFF6FF`.
- **Inactive State:** Icon and label tinted `#94A3B8` (Slate 400).
- **Container Specs:** Background `#FFFFFF`, height `64px` (+ safe area inset), subtle top border `1px solid #F1F5F9`, ambient upward shadow.

### 4. Buttons
- **Primary:** Solid `#165DFF` fill, text `#FFFFFF`, border-radius `12px`, height `48px`. Active state shifts to `#0E46D7`.
- **Secondary / Soft:** Background `#EFF6FF`, text `#165DFF`, border-radius `12px`, height `48px`.
- **Ghost:** Transparent background, text `#475569`, hover/pressed state `#F1F5F9`.

### 5. Input Fields
- **Container:** Height `48px`, background `#FFFFFF`, border `1px solid #E2E8F0`, corner radius `12px`, padding `0 14px`.
- **Focus State:** Border `#165DFF`, subtle outer ring `0 0 0 3px rgba(22, 93, 255, 0.15)`.
- **Placeholder:** `#94A3B8`, font weight 400.

### 6. Lists & Cell Items
- Dividers are styled with `#F1F5F9`. Cell rows have a minimum touch target of `52px` with right-aligned chevron arrows (`#CBD5E1`) for navigable sub-screens.