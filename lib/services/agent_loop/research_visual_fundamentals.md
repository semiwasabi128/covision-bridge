# Visual Design Fundamentals for Flutter Desktop Apps

Reference guide for BridgeDS dark theme design system.
Canvas: `#07080A`, Surface: `#101111`, Accent: `#5B76FE`

---

## 1. Color Theory

### Contrast Ratios (WCAG 2.1)
- **Normal text (< 18pt)**: 4.5:1 minimum
- **Large text (≥ 18pt or 14pt bold)**: 3:1 minimum
- **UI components & graphics**: 3:1 minimum
- **Enhanced (AAA)**: 7:1 normal text, 4.5:1 large text

**Calculate contrast ratio:**
```
Relative Luminance (L) = 
  for RGB ≤ 0.03928: RGB/12.92
  for RGB > 0.03928: ((RGB+0.055)/1.055)^2.4

Contrast Ratio = (L1 + 0.05) / (L2 + 0.05)
where L1 is lighter color
```

**BridgeDS specific:**
- Canvas `#07080A` (L ≈ 0.003) vs White `#FFFFFF` (L = 1.0) = **20.6:1** ✓
- Surface `#101111` (L ≈ 0.005) vs White = **19.8:1** ✓
- AccentMiro `#5B76FE` (L ≈ 0.28) vs Canvas = **11.2:1** ✓

### Color Harmony Models

**Complementary** (180° apart)
- High contrast, vibrant
- Use 1 dominant, 1 accent
- Example: Blue `#5B76FE` ↔ Orange `#FE955B`

**Analogous** (30° apart)
- Harmonious, low contrast
- 3 adjacent colors on wheel
- Example: `#5B76FE` → `#765BFE` → `#AA5BFE`

**Triadic** (120° apart)
- Balanced, vibrant
- Equal visual weight
- Example: `#5B76FE`, `#76FE5B`, `#FE5B76`

**Split-Complementary**
- Base + 2 adjacent to complement
- Less tension than complementary
- Example: `#5B76FE` + `#FEDA5B` + `#FE955B`

### 60-30-10 Rule
- **60%**: Dominant (canvas/background) → `#07080A`
- **30%**: Secondary (surface/cards) → `#101111`
- **10%**: Accent (CTAs/highlights) → `#5B76FE`

### Color Psychology in Dark Mode

**Blues** (`#5B76FE`)
- Trust, stability, productivity
- Reduced eye strain in dark mode
- Use for primary actions, links

**Purples**
- Creativity, premium, luxury
- Good for pro features

**Greens**
- Success, growth, positive actions
- Confirm buttons, success states

**Reds**
- Error, danger, urgency
- Destructive actions, alerts

**Yellows/Oranges**
- Warning, attention
- Use sparingly—high contrast in dark mode

**Dark Mode Specific:**
- Avoid pure white (`#FFFFFF`)—use `#E8E8E8` or `#F5F5F5`
- Avoid pure black backgrounds—use dark grays (`#07080A`, `#101111`)
- Reduce saturation 10-20% vs light mode
- Increase luminance for readability

---

## 2. Typography

### Font Pairing Rules

**1. Contrast in Style**
- Serif (headings) + Sans-serif (body)
- Display (titles) + Geometric (UI)
- Avoid pairing similar fonts

**2. Contrast in Weight**
- Bold headings + Regular body
- Light display + Medium body

**3. Same superfamily**
- Roboto + Roboto Condensed
- Inter + Inter Display

**4. Proven Pairs**
- **Classic**: Playfair Display + Source Sans Pro
- **Modern**: Montserrat + Open Sans
- **Tech**: Inter + Roboto Mono
- **macOS Native**: SF Pro Display + SF Pro Text

**Flutter macOS Recommendation:**
- **UI**: SF Pro Text (system default)
- **Display**: SF Pro Display
- **Mono**: SF Mono

### Type Scale Ratios

| Ratio | Name | Character |
|-------|------|-----------|
| 1.125 | Major Second | Subtle, tight vertical rhythm |
| 1.200 | Minor Third | **Recommended for desktop** |
| 1.250 | Major Third | Spacious, editorial |
| 1.333 | Perfect Fourth | Strong hierarchy |
| 1.414 | Augmented Fourth | Dramatic |
| 1.500 | Perfect Fifth | Very dramatic |
| 1.618 | Golden Ratio | Maximum contrast |

**Example Scale (1.200 ratio, 16px base):**
```
xs:   12px  (16 ÷ 1.2²)
sm:   13px  (16 ÷ 1.2)
base: 16px
md:   19px  (16 × 1.2)
lg:   23px  (16 × 1.2²)
xl:   28px  (16 × 1.2³)
2xl:  33px  (16 × 1.2⁴)
3xl:  40px  (16 × 1.2⁵)
4xl:  48px  (16 × 1.2⁶)
```

**Flutter Implementation:**
```dart
static const double scale = 1.2;
static const double base = 16.0;

// Type scale
static const double xs = base / (scale * scale);      // 11.11
static const double sm = base / scale;                // 13.33
static const double md = base * scale;                // 19.20
static const double lg = base * scale * scale;        // 23.04
static const double xl = base * scale * scale * scale; // 27.65
```

### Line Height (Leading)

**Body Text**: 1.4 - 1.6
- Short lines (45-55 chars): 1.4
- Medium lines (55-75 chars): 1.5 (recommended)
- Long lines (75+ chars): 1.6

**Headings**: 1.1 - 1.3
- Display/Hero: 1.0 - 1.1
- H1-H2: 1.1 - 1.2
- H3-H6: 1.2 - 1.3

**UI Elements**: 1.0 - 1.2
- Buttons: 1.0
- Menu items: 1.2
- Form labels: 1.3

**Flutter:**
```dart
// Body
TextStyle(fontSize: 16, height: 1.5)  // 24px line height

// Heading
TextStyle(fontSize: 32, height: 1.2)  // 38.4px line height
```

### Letter Spacing (Tracking)

**Large Text** (> 24px): -0.01em to -0.03em
- Tighter tracking for display sizes
- `-0.02em` is safe default

**Body Text** (14-18px): 0 to 0.01em
- Optical balance, usually 0

**Small Text** (< 14px): 0.02em to 0.05em
- Increase readability
- `0.03em` for 12px text

**All Caps**: 0.05em to 0.1em
- Always add tracking
- `0.08em` recommended

**Flutter:**
```dart
// Display
TextStyle(fontSize: 48, letterSpacing: -0.02 * 48)  // -0.96

// Small caps
TextStyle(fontSize: 12, letterSpacing: 0.08 * 12)   // 0.96
```

### Font Weight Hierarchy

| Weight | Value | Use Case |
|--------|-------|----------|
| Thin | 100 | Rarely—decorative only |
| ExtraLight | 200 | Large display text |
| Light | 300 | Subheadings, secondary |
| Regular | 400 | **Body text default** |
| Medium | 500 | **Emphasis, UI labels** |
| SemiBold | 600 | **Headings, buttons** |
| Bold | 700 | Strong emphasis |
| ExtraBold | 800 | Rarely—high contrast |
| Black | 900 | Display only |

**Desktop App Pattern:**
- Body: 400 (Regular)
- Emphasis: 500 (Medium)
- Headings: 600 (SemiBold)
- CTAs: 600 (SemiBold)

---

## 3. Spacing Systems

### 8pt Grid System

**Base unit**: 4px (half-step)
**Rhythm**: 8px (full-step)

**Scale:**
```
0:   0px
0.5: 2px   (rare—borders, dividers)
1:   4px   (tight spacing)
2:   8px   (base rhythm)
3:   12px
4:   16px  (common padding)
5:   20px
6:   24px  (section spacing)
8:   32px
10:  40px
12:  48px  (large sections)
16:  64px
20:  80px
24:  96px  (page margins)
```

**Flutter:**
```dart
class Spacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}
```

**Usage Rules:**
- Component padding: 16px (2 × 8)
- Between elements: 8px, 16px, 24px
- Section margins: 32px, 48px
- Page margins: 64px, 96px

### Golden Ratio Spacing (1.618)

**Alternative to 8pt for organic layouts:**
```
Base: 16px
Step 1: 16 × 1.618 = 26px
Step 2: 26 × 1.618 = 42px
Step 3: 42 × 1.618 = 68px
Step 4: 68 × 1.618 = 110px
```

**When to use:**
- Marketing pages, hero sections
- Card layouts with variable content
- Organic, non-grid layouts

**8pt grid preferred for:**
- UI components, forms
- Navigation, toolbars
- Pixel-perfect alignment

### Modular Scale (Combined)

**Type + Space Harmony:**
Use same ratio for both type and space (e.g., 1.2)

```dart
const double ratio = 1.2;
const double base = 16.0;

double scale(int step) => base * pow(ratio, step);

// Unified scale
scale(-2) = 11px  // xs text, tight space
scale(-1) = 13px  // sm text, small space
scale(0)  = 16px  // base
scale(1)  = 19px  // md text, medium space
scale(2)  = 23px  // lg text, large space
scale(3)  = 28px
scale(4)  = 33px
```

---

## 4. Shadow & Elevation

### Material Design Elevation Levels

| Level | Use Case | Elevation (dp) | Shadow |
|-------|----------|----------------|--------|
| 0 | Canvas, background | 0 | None |
| 1 | Cards, surfaces | 1-2 | Subtle |
| 2 | Raised buttons, search | 3-4 | Soft |
| 3 | Modals, dialogs | 8 | Medium |
| 4 | Navigation drawer | 16 | Strong |
| 5 | Menu, picker | 24 | Very strong |

**Light Mode Shadows (0-5):**
```css
/* Level 1 */
box-shadow: 0 1px 3px rgba(0,0,0,0.12), 
            0 1px 2px rgba(0,0,0,0.24);

/* Level 2 */
box-shadow: 0 3px 6px rgba(0,0,0,0.15), 
            0 2px 4px rgba(0,0,0,0.12);

/* Level 3 */
box-shadow: 0 10px 20px rgba(0,0,0,0.15), 
            0 3px 6px rgba(0,0,0,0.10);

/* Level 4 */
box-shadow: 0 15px 25px rgba(0,0,0,0.15), 
            0 5px 10px rgba(0,0,0,0.05);

/* Level 5 */
box-shadow: 0 20px 40px rgba(0,0,0,0.20);
```

### Dark Mode Elevation (Color-based)

**Key principle:** In dark mode, elevation = lighter surface, NOT shadows.

**BridgeDS Elevation Scale (Material Design 3):**
```dart
// Base surfaces
Canvas:   #07080A  (L = 0.003)  // Level 0
Surface:  #101111  (L = 0.005)  // Level 1

// Elevated surfaces (add white overlay per Material Design)
Level 1:  #101111 + 5% white   = #181919
Level 2:  #101111 + 8% white   = #1E1F1F
Level 3:  #101111 + 11% white  = #242525
Level 4:  #101111 + 12% white  = #252626
Level 5:  #101111 + 14% white  = #292A2A

// Material Design 3 official overlay percentages:
// 0dp: 0%, 1dp: 5%, 2dp: 8%, 3dp: 11%, 4dp: 12%, 6dp: 14%
```

**Formula:**
```dart
Color elevate(Color base, int level) {
  final overlay = (level * 0.04).clamp(0.0, 0.16);
  return Color.lerp(base, Colors.white, overlay)!;
}
```

**Optional subtle shadows in dark mode:**
```css
/* Very subtle, for depth cue only */
box-shadow: 0 4px 8px rgba(0,0,0,0.4);
```

### Box-Shadow Layering

**Multi-layer shadows for realism:**

**Concept:**
- Layer 1: Soft, large, distant (ambient)
- Layer 2: Sharp, small, close (direct)

**Example:**
```css
/* Floating card */
box-shadow: 
  0 2px 4px rgba(0,0,0,0.1),    /* Direct light */
  0 8px 16px rgba(0,0,0,0.1);   /* Ambient shadow */

/* Dropdown menu */
box-shadow:
  0 0 1px rgba(0,0,0,0.3),      /* Border hint */
  0 4px 8px rgba(0,0,0,0.15),   /* Close shadow */
  0 12px 24px rgba(0,0,0,0.15); /* Far shadow */
```

**Flutter (Container decoration):**
```dart
BoxDecoration(
  color: BridgeColors.surface,
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ],
)
```

**Dark mode Flutter:**
```dart
BoxDecoration(
  // Use color elevation instead of shadow
  color: elevate(BridgeColors.surface, 2),
  // Optional: very subtle shadow
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ],
)
```

---

## 5. WCAG 2.1 AA Compliance

### Contrast Requirements

| Content Type | AA | AAA |
|--------------|-----|-----|
| Normal text (< 18pt / < 14pt bold) | **4.5:1** | 7:1 |
| Large text (≥ 18pt / ≥ 14pt bold) | **3:1** | 4.5:1 |
| UI components (buttons, inputs) | **3:1** | — |
| Graphical objects (icons, charts) | **3:1** | — |
| Inactive/disabled elements | None | — |

### How to Calculate Contrast Ratio

**Step 1: Convert hex to RGB (0-255)**
```
#5B76FE → R=91, G=118, B=254
```

**Step 2: Convert to sRGB (0-1)**
```
R = 91/255  = 0.357
G = 118/255 = 0.463
B = 254/255 = 0.996
```

**Step 3: Calculate relative luminance (L)**
```
For each channel (R, G, B):
  if channel ≤ 0.03928:
    channel_linear = channel / 12.92
  else:
    channel_linear = ((channel + 0.055) / 1.055) ^ 2.4

L = 0.2126 × R_linear + 0.7152 × G_linear + 0.0722 × B_linear
```

**Example for #5B76FE:**
```
R_linear = ((0.357 + 0.055) / 1.055) ^ 2.4 = 0.111
G_linear = ((0.463 + 0.055) / 1.055) ^ 2.4 = 0.184
B_linear = ((0.996 + 0.055) / 1.055) ^ 2.4 = 0.992

L = 0.2126 × 0.111 + 0.7152 × 0.184 + 0.0722 × 0.992
L = 0.024 + 0.132 + 0.072 = 0.228
```

**Step 4: Calculate contrast ratio**
```
Contrast = (L_lighter + 0.05) / (L_darker + 0.05)

#5B76FE (L=0.228) vs #07080A (L=0.003):
Contrast = (0.228 + 0.05) / (0.003 + 0.05)
         = 0.278 / 0.053
         = 5.24:1 ✓ (passes AA for normal text)
```

**Step 5: Validate**
- **5.24:1 ≥ 4.5:1** → ✓ AA normal text
- **5.24:1 ≥ 3:1** → ✓ AA large text
- **5.24:1 < 7:1** → ✗ AAA normal text

### BridgeDS Validation Matrix

| Foreground | Background | Ratio | AA Normal | AA Large | AAA Normal |
|------------|------------|-------|-----------|----------|------------|
| `#FFFFFF` | `#07080A` | 20.6:1 | ✓ | ✓ | ✓ |
| `#E8E8E8` | `#07080A` | 17.8:1 | ✓ | ✓ | ✓ |
| `#5B76FE` | `#07080A` | 11.2:1 | ✓ | ✓ | ✓ |
| `#5B76FE` | `#101111` | 10.8:1 | ✓ | ✓ | ✓ |
| `#FFFFFF` | `#5B76FE` | 2.1:1 | ✗ | ✗ | ✗ |

**Warning:** `#5B76FE` accent on white backgrounds fails AA. Use darker variant `#4A5FD9` (3.2:1) for light mode.

### Flutter Contrast Checker

```dart
class ContrastChecker {
  static double luminance(Color color) {
    double channelLuminance(int channel) {
      final c = channel / 255.0;
      return c <= 0.03928 
        ? c / 12.92 
        : pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    
    final r = channelLuminance(color.red);
    final g = channelLuminance(color.green);
    final b = channelLuminance(color.blue);
    
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  
  static double contrastRatio(Color fg, Color bg) {
    final l1 = luminance(fg);
    final l2 = luminance(bg);
    final lighter = max(l1, l2);
    final darker = min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }
  
  static bool meetsAA(Color fg, Color bg, {bool largeText = false}) {
    final ratio = contrastRatio(fg, bg);
    return largeText ? ratio >= 3.0 : ratio >= 4.5;
  }
  
  static bool meetsAAA(Color fg, Color bg, {bool largeText = false}) {
    final ratio = contrastRatio(fg, bg);
    return largeText ? ratio >= 4.5 : ratio >= 7.0;
  }
}
```

### Quick Testing Tools

**Online:**
- WebAIM Contrast Checker: https://webaim.org/resources/contrastchecker/
- Coolors Contrast Checker: https://coolors.co/contrast-checker
- Color Review: https://color.review/

**Browser DevTools:**
- Chrome: Inspect element → Contrast ratio in color picker
- Firefox: Accessibility inspector

**CLI:**
```bash
# Install contrast-ratio npm package
npm install -g contrast-ratio

# Check ratio
contrast-ratio "#5B76FE" "#07080A"
# Output: 11.2:1 (AA ✓, AAA ✓)
```

---

## Quick Reference Card

### BridgeDS Dark Theme

```dart
// Colors
canvas:     #07080A  (L=0.003)
surface:    #101111  (L=0.005)
accentMiro: #5B76FE  (L=0.228)
textPrimary: #FFFFFF (L=1.0, 20.6:1 vs canvas)

// Typography
base: 16px, ratio: 1.2
lineHeight: 1.5 (body), 1.2 (headings)
fontWeight: 400 (body), 600 (headings)

// Spacing
base: 8px (multiples of 8)
padding: 16px (components)
margin: 24px (sections)

// Elevation (Material Design 3)
Level 0: #07080A (0dp)
Level 1: #181919 (+5% white, 1dp)
Level 2: #1E1F1F (+8% white, 2dp)
Level 3: #242525 (+11% white, 3dp)

// Contrast
AA normal: 4.5:1 ✓
AA large: 3.0:1 ✓
UI components: 3.0:1 ✓
```

### Common Pitfalls

1. **Don't use pure black (`#000000`)** in dark mode—too harsh
2. **Don't rely only on color** for state—add icons/text
3. **Don't use white text on accent** (`#FFFFFF` on `#5B76FE` = 2.1:1 ✗)
4. **Don't mix spacing systems**—stick to 8pt grid
5. **Don't use shadows for elevation in dark mode**—use lighter surfaces

### Validation Checklist

- [ ] All text contrast ≥ 4.5:1 (or 3:1 for large)
- [ ] UI components contrast ≥ 3:1
- [ ] Spacing multiples of 8px
- [ ] Type scale consistent (same ratio)
- [ ] Elevation expressed through color (dark mode)
- [ ] Font weights: 400, 500, 600 (avoid thin/black)
- [ ] Line height 1.5 for body, 1.2 for headings

---

**Last updated:** 2026-07-18
**Target platform:** Flutter macOS Desktop
**Theme:** BridgeDS Dark
