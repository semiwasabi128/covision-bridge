# UI/UX Principles for Flutter Desktop AI Agent

**Context**: BridgeDS dark theme, macOS desktop app with 64px top bar, 240px sidebar, dashboard grid homepage.

---

## 1. Gestalt Principles

### Proximity
- **Rule**: Elements 8-16px apart are perceived as related; 24px+ creates separation
- **UI Examples**:
  - Form field label: 4px from input
  - Related actions: 8px gap between buttons
  - Card spacing: 16-24px between cards
  - Section spacing: 40-48px between major sections

### Similarity
- **Rule**: Similar visual properties = similar function/meaning
- **UI Examples**:
  - All primary actions use same color (e.g., #0066FF)
  - All text inputs share border style and height
  - All icons in navigation use same size (20-24px)
  - Consistent typography for same content types

### Continuity
- **Rule**: Eye follows paths, lines, curves naturally
- **UI Examples**:
  - Form fields stacked vertically create reading flow
  - Progress bars/steppers guide through multi-step processes
  - Timeline views use vertical line to connect events
  - Grid alignment creates implied lines

### Closure
- **Rule**: Mind completes incomplete shapes/patterns
- **UI Examples**:
  - Partial borders (bottom-only) still define containers
  - Dotted outlines suggest clickable drop zones
  - Skeleton screens use partial shapes during loading
  - Truncated text with "..." implies continuation

### Figure-Ground
- **Rule**: Clear distinction between foreground content and background
- **UI Examples**:
  - Modal overlays: content on dark backdrop (opacity 0.6-0.8)
  - Cards: elevated surface (#1E1E1E) on darker background (#121212)
  - Focus states: bright border distinguishes active element
  - Sidebar: distinct background color from main content area

### Common Region
- **Rule**: Borders/backgrounds group related elements
- **UI Examples**:
  - Cards with 1px border or background color
  - Table rows with alternating backgrounds (zebra striping)
  - Input groups with shared container border
  - Section panels with subtle background tint

---

## 2. Fitts's Law

### Core Principle
**Time to acquire target = a + b × log₂(D/W + 1)**
- D = distance to target
- W = width of target

### Concrete Rules
- **Minimum touch target**: 44×44px (Apple HIG)
- **Desktop mouse target**: 32×32px minimum, 40×40px comfortable
- **Primary actions**: Larger targets (48-56px height for buttons)
- **Edges & corners**: Infinite width — use for frequent actions
  - macOS menu bar: top edge
  - Dock: bottom edge
  - Window controls: top corners

### Application
- **Button sizing**:
  - Small: 32px height (tertiary actions)
  - Medium: 40px height (standard)
  - Large: 48px height (primary CTAs)
- **Icon buttons**: 40×40px minimum clickable area
- **Dropdown triggers**: Full width clickable, not just icon
- **Close buttons**: Top-right corner, 32×32px minimum

### Desktop Advantages
- **Right-click context menus**: Appears at cursor (D=0)
- **Toolbar icons**: Group frequently-used at top edge
- **Sidebar items**: Full width clickable, not just text
- **Command palette**: Launches at keyboard shortcut (no mouse travel)

---

## 3. Hick's Law

### Core Principle
**Decision time = b × log₂(n + 1)**
- n = number of choices

### Concrete Rules
- **7±2 items**: Miller's Law — limit menu items to 5-9
- **Progressive disclosure**: Hide advanced options behind "More" or toggle
- **Sensible defaults**: Pre-select most common option
- **Categorization**: Group 20+ items into 3-5 categories

### UI Patterns
- **Navigation**: Max 7 top-level items; nest others in submenus
- **Toolbars**: Show 5-7 primary actions; overflow menu for rest
- **Settings**: Group into tabs/sections (General, Advanced, etc.)
- **Search filters**: Collapsed by default, expand on demand
- **Action menus**: 3-5 common actions visible, "More actions" for rest

### Desktop-Specific
- **Keyboard shortcuts**: Reduce choices to keypress
- **Command palette**: Type-to-filter reduces visual choices
- **Recent items**: Surface last 5-7, avoid showing all history
- **Multi-step wizards**: Break complex forms into 3-5 steps

---

## 4. Visual Hierarchy

### Size
- **H1**: 32-40px (page titles)
- **H2**: 24-28px (section headers)
- **H3**: 20-22px (subsections)
- **Body**: 14-16px (standard text)
- **Caption**: 12-13px (metadata, labels)
- **Scale ratio**: 1.25 (Major Third) or 1.333 (Perfect Fourth)

### Contrast
- **Dark theme**:
  - Primary text: #FFFFFF or rgba(255,255,255,0.95)
  - Secondary text: rgba(255,255,255,0.70)
  - Tertiary text: rgba(255,255,255,0.50)
  - Disabled text: rgba(255,255,255,0.38)
- **Weight**: Bold (700) for emphasis, Medium (500) for headers, Regular (400) for body

### Spacing
- **Vertical rhythm**: 8px base unit
  - Tight: 4px (label to input)
  - Normal: 8-12px (between paragraphs)
  - Loose: 16-24px (between sections)
  - Section: 40-48px (major divisions)
- **Line height**: 1.5 (24px for 16px text) for body, 1.2-1.3 for headers

### Color
- **Primary**: Accent color for CTAs (#0066FF typical)
- **Semantic colors**:
  - Success: #34C759
  - Warning: #FF9500
  - Error: #FF3B30
  - Info: #0A84FF
- **Hierarchy by color**: Bright = important, muted = secondary

### Position
- **F-pattern**: Left to right, top to bottom (text-heavy content)
- **Z-pattern**: Logo top-left → CTA top-right → diagonal → CTA bottom-right
- **Priority placement**:
  1. Top-left: Logo, brand
  2. Top-right: User profile, global actions
  3. Center: Primary content
  4. Bottom-right: Confirmation actions (Save, Submit)

---

## 5. Whitespace

### Micro Whitespace (Internal)
- **Between letters**: Tracking +0.02em for ALL CAPS
- **Between lines**: Line height 1.5× font size (24px for 16px text)
- **Around icons**: 8-12px margin from adjacent text
- **Button padding**: 12-16px horizontal, 8-12px vertical

### Macro Whitespace (External)
- **Card margins**: 16-24px around content
- **Section spacing**: 40-64px between major sections
- **Page margins**: 24-32px on desktop, responsive on mobile
- **Content max-width**: 1200-1400px for readability, centered

### Information Density
- **Low density** (spacious): 
  - Landing pages, dashboards
  - 40-60% whitespace
  - Large cards (300-400px wide)
- **Medium density** (comfortable):
  - Standard app views
  - 30-40% whitespace
  - Grid with 16-24px gutters
- **High density** (compact):
  - Data tables, admin tools
  - 20-30% whitespace
  - Tight padding (8-12px), smaller fonts (13-14px)

### Desktop-Specific
- **Sidebar**: 16-24px padding inside
- **Content area**: 32-48px padding from edges
- **Modal dialogs**: 24-32px padding, 40-60% screen width max
- **Empty states**: Large illustration (200-300px), generous spacing (32-48px)

---

## 6. Affordance & Feedback

### Signifiers (Visual Cues)
- **Clickable elements**:
  - Cursor: pointer on hover
  - Color: Blue/accent for links
  - Underline: Links in body text
  - Border/background: Buttons clearly defined
- **Draggable**: Cursor changes to grab/grabbing
- **Editable**: Border appears on focus, cursor changes to I-beam
- **Disabled**: 38% opacity, cursor default (not-allowed if attempted)

### Hover States
- **Buttons**: Background lightens 10-15% or darkens for dark theme
- **Cards**: Subtle elevation increase (shadow), border appears
- **List items**: Background highlight (rgba(255,255,255,0.08))
- **Icons**: Color change or slight scale (1.05×)
- **Timing**: 150-200ms transition duration

### Active States
- **Click feedback**: Background darkens further, slight scale down (0.98×)
- **Selected items**: Distinct background color, accent border
- **Focus ring**: 2-3px border, accent color, 4px offset
- **Pressed buttons**: Inset shadow, 2-3px Y-offset

### Loading States
- **Inline spinners**: 16-24px, accent color, appears after 300ms delay
- **Skeleton screens**: Animated gradient sweep, match content layout
- **Progress bars**: Determinate (0-100%) or indeterminate pulse
- **Optimistic updates**: Show result immediately, revert on error

### Empty States
- **Components**:
  - Illustration (200-300px, centered)
  - Heading (20-24px): "No items yet"
  - Body text (14-16px): Brief explanation
  - CTA button (48px height): "Create your first..."
- **Spacing**: 24-32px between components
- **Zero data vs error**: Different illustrations/messaging

---

## 7. Layout & Composition

### Grid Systems
- **12-column grid**: Desktop standard
  - Container: 1200-1400px max
  - Gutter: 24-32px
  - Column width: Fluid, ~80-100px typical
  - Usage: 3-col (4-span each), 4-col (3-span each), sidebar+content (3+9)
- **8pt grid**: All dimensions multiples of 8
  - Spacing: 8, 16, 24, 32, 40, 48, 64px
  - Component heights: 32, 40, 48, 56, 64px
  - Benefits: Consistent scaling, easier math

### Alignment
- **Left-aligned**: Default for text (LTR languages)
- **Center-aligned**: Headings, modals, empty states
- **Right-aligned**: Numbers, timestamps, actions in tables
- **Grid alignment**: Snap to columns, not arbitrary positions
- **Baseline alignment**: Text in same row shares baseline

### Balance
- **Symmetrical**: 
  - Formal, stable
  - Dashboard with equal-width cards
  - Centered modals
  - Login/signup pages
- **Asymmetrical**:
  - Dynamic, interesting
  - Sidebar (240px) + content (fluid)
  - 2:1 split panes
  - Off-center hero sections

### Rhythm
- **Repetition**: Consistent spacing creates visual tempo
- **Pattern**: Card → 24px gap → Card → 24px gap
- **Alternation**: Zebra striping in tables (every other row)
- **Sequence**: Step indicators with equal spacing

### Proportion
- **Golden ratio**: 1:1.618 (sidebar 240px, content 388px) — rarely practical
- **Rule of thirds**: Divide space into 3 equal parts, place focal points at intersections
- **Common ratios**:
  - 2:1 (sidebar-content split)
  - 3:2 (image aspect ratios)
  - 4:3 (legacy screen ratio)
  - 16:9 (video/modern screens)

### Visual Weight
- **Heavier elements**:
  - Larger size, darker colors, bold text
  - High contrast, saturated colors
  - Irregular shapes, dense textures
- **Balance**: Distribute weight evenly (symmetrical) or counterbalance (asymmetrical)
- **Example**: Large image (left) balanced by multiple text blocks (right)

---

## 8. Desktop UI Patterns

### Sidebar Navigation
- **Width**: 240px (collapsed: 64px icon-only)
- **Structure**:
  - Logo/brand: Top, 64px height
  - Navigation items: 40-48px height, left-aligned
  - Icon: 20-24px, 16px left margin
  - Label: 16px from icon
  - Hover: Full-width background highlight
- **Sections**: Divide with 8px gap or 1px divider
- **Footer**: Settings/profile at bottom, 48-56px height

### Top Bar (64px)
- **Left**: Breadcrumbs, back button, or title
- **Center**: Search bar (400-600px max) or title
- **Right**: Notifications, user profile, global actions
- **Vertical alignment**: Center content vertically
- **Divider**: 1px border-bottom for separation

### Dashboard Grid
- **Layout**: CSS Grid or 12-column grid
- **Card sizes**:
  - Small: 1-2 columns (200-400px)
  - Medium: 3-4 columns (600-800px)
  - Large: 6-12 columns (full width)
- **Gap**: 16-24px
- **Responsive**: 3-col → 2-col → 1-col

### Command Palette
- **Trigger**: ⌘K or Ctrl+K
- **Position**: Top-center, 40-60% screen width, 600px max
- **Search input**: 48-56px height, autofocus
- **Results**: 40-48px item height, max 8-10 visible (scroll rest)
- **Navigation**: Arrow keys, Enter to select, Esc to close
- **Features**: Fuzzy search, recent items, keyboard shortcuts shown

### Split Pane
- **Divider**: 1px line or 8px draggable handle
- **Resize**: Drag divider, snap to min/max widths
- **Proportions**: 
  - 50/50 (equal)
  - 60/40 or 40/60 (content-heavy)
  - 70/30 (main + sidebar)
- **Min width**: 200-300px to prevent collapse
- **Persist**: Save split position in preferences

### Density Modes
- **Compact**:
  - Row height: 32px
  - Padding: 8px
  - Font: 13-14px
  - Use: Data tables, power users
- **Comfortable** (default):
  - Row height: 40-48px
  - Padding: 12-16px
  - Font: 14-16px
  - Use: Standard app views
- **Spacious**:
  - Row height: 56-64px
  - Padding: 16-24px
  - Font: 16-18px
  - Use: Accessibility, touch-friendly

### Keyboard-First Design
- **Tab navigation**: All interactive elements reachable
- **Focus indicators**: Visible 2-3px ring, high contrast
- **Shortcuts**: 
  - Single key: Delete, Escape, Enter, Space
  - Modifier combos: ⌘N (new), ⌘S (save), ⌘F (find)
  - Display: Show shortcuts in tooltips, menus
- **Shortcut overlay**: ? or ⌘/ to show all shortcuts
- **Focus management**: 
  - Modal opens → focus first input
  - Modal closes → return focus to trigger
  - Delete item → focus next or previous

---

## 9. macOS Human Interface Guidelines

### Menu Bar
- **App menu**: Application name, About, Preferences (⌘,), Quit (⌘Q)
- **File menu**: New, Open, Save, Close, Print
- **Edit menu**: Undo, Cut, Copy, Paste, Select All
- **View menu**: Show/Hide sidebars, Enter Full Screen
- **Window menu**: Minimize, Zoom, Bring All to Front
- **Help menu**: Search, app-specific help
- **Icons**: No icons in menus (text-only exception: macOS standard)
- **Shortcuts**: Show to right, use standard conventions

### Window Chrome
- **Title bar**: 52px height (with toolbar: 78px)
- **Traffic lights**: Top-left, 12px from edge
  - Red: Close (⌘W)
  - Yellow: Minimize (⌘M)
  - Green: Full screen/zoom
- **Title**: Centered or left-aligned with icon
- **Toolbar**: 48px height, 16px padding, standard macOS style
- **Unified title/toolbar**: Title bar and toolbar combined (single background)

### Sidebar + Content Area Split
- **Sidebar**: 
  - Width: 180-280px (240px common)
  - Background: Slightly darker/lighter than content
  - Source list style: Rounded selection, inset from edges
  - Resizable: Drag divider, 150px min
- **Content area**:
  - Full height, white/canvas background
  - Padding: 20-32px
  - Toolbar: Optional 48px height at top
- **Divider**: 1px vertical line, slightly transparent

### Toolbar Patterns
- **Segmented controls**: 2-5 options, 28-32px height
- **Icon buttons**: 32×32px, monochrome SF Symbols
- **Search field**: 150-200px, rounded, SF Symbols magnifying glass
- **Flexible space**: Auto-distributes toolbar items
- **Item spacing**: 8-16px between groups, 4-8px within groups

### macOS-Specific Controls
- **NSButton**: 
  - Primary: Blue accent, rounded
  - Secondary: Gray border, transparent background
  - Help button: ? icon, circular, right-aligned in dialogs
- **NSPopUpButton**: Dropdown with ▼ indicator, 24-26px height
- **NSSlider**: Continuous or discrete, tick marks optional
- **NSStepper**: +/- buttons, 16px height, attached to number field
- **NSSwitch**: Toggle switch (not checkbox for boolean settings)

### Spacing & Metrics
- **Dialog margins**: 20px all sides
- **Button spacing**: 12-14px between Cancel and primary action
- **Label to control**: 8px vertical gap
- **Section spacing**: 20-28px between grouped controls
- **Disclosure triangle**: 8px left of collapsible section label

### Typography
- **SF Pro**: System font (auto-loads, don't bundle)
- **Sizes**:
  - Title: 18-22px, Bold
  - Headline: 16-18px, Semibold
  - Body: 13-14px (desktop), Regular or Medium
  - Caption: 11-12px, Regular
- **Line height**: 1.2-1.4 for UI text (tighter than web)
- **Color**: Use system dynamic colors for automatic light/dark mode

### Vibrancy & Materials
- **Sidebar**: NSVisualEffectView with .sidebar material
- **Menus**: .menu material (translucent, adapts to wallpaper)
- **Popovers**: .popover material
- **Blurs**: Backdrop blur behind modals/sheets
- **Avoid**: Custom blur implementations, use system materials

### Notifications & Alerts
- **Sheets**: Modal that drops from title bar, 400-600px wide
- **Alerts**: Centered modal, 280-360px wide, 2-3 buttons max
- **Icons**: App icon (left), 64×64px
- **Buttons**: Right-aligned, default action is rightmost (blue)
- **Avoid overuse**: Don't interrupt flow with excessive confirmations

---

## Quick Reference: Key Numbers

| Element | Dimension | Notes |
|---------|-----------|-------|
| Top bar height | 64px | macOS toolbar: 48-78px |
| Sidebar width | 240px | Collapsed: 64px |
| Min touch target | 44×44px | Desktop: 32px ok, 40px better |
| Button height | 40-48px | Small: 32px, Large: 56px |
| Icon size | 20-24px | Toolbar: 16-20px |
| Body text | 14-16px | macOS: 13-14px |
| Line height | 1.5 | UI text: 1.2-1.4 |
| Spacing unit | 8px | 8pt grid base |
| Card gap | 16-24px | Dashboard/grid layouts |
| Section gap | 40-48px | Major divisions |
| Modal width | 40-60% | Max: 600-800px |
| Content max-width | 1200-1400px | Readability |
| Grid columns | 12 | Desktop standard |
| Grid gutter | 24-32px | Between columns |
| Max menu items | 5-9 | Hick's Law (7±2) |
| Focus ring | 2-3px | 4px offset |
| Transition | 150-200ms | Hover/active states |

---

## Flutter Desktop Implementation Notes

### Responsive Breakpoints
```dart
// Desktop-specific breakpoints
const double compactWidth = 1280;
const double mediumWidth = 1600;
const double largeWidth = 1920;
```

### macOS-Specific Widgets
- `CupertinoButton` for macOS-style buttons
- `CupertinoTextField` for search fields
- `CupertinoSwitch` for toggles
- Use `macos_ui` package for native macOS controls

### Dark Theme Considerations
- Test contrast ratios (WCAG AA: 4.5:1 for text)
- Use opacity for text hierarchy, not pure gray
- Accent colors should work on dark backgrounds
- Avoid pure black (#000000), use #121212 or similar

### Performance
- Avoid overdraw: minimize overlapping opaque layers
- Use `RepaintBoundary` for complex widgets that don't change
- Lazy-load dashboard cards, virtualize long lists
- Cache images, use `cached_network_image` package

### Accessibility
- Semantic labels for screen readers
- Keyboard navigation (tab order, shortcuts)
- High contrast mode support
- Scalable text (respect system font size)

---

**Last Updated**: 2026-07-18  
**Target Platform**: Flutter macOS Desktop (BridgeDS)  
**Purpose**: AI Agent Design Knowledge Base
