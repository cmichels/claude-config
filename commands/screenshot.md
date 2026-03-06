---
description: "Capture annotated Playwright screenshots with title banners and box+callout highlights over DOM elements. Usage: /screenshot <description> [--selectors \".sel1 => Label, .sel2 => Label\"] [--dir ./path] [--no-annotate]"
allowed_tools: Read, Write, Bash, Glob, AskUserQuestion, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_snapshot
---

# Screenshot Command

Capture the current Playwright browser page as an annotated screenshot with a title banner and box+callout highlights over specified DOM elements.

**Arguments:** `$ARGUMENTS`

---

## Step 0: Parse Arguments

Parse `$ARGUMENTS` into:
- `$DESCRIPTION` — everything before the first `--` flag
- `--selectors` — optional, comma-separated CSS selectors with optional labels (e.g. `".header => Column renamed, .tooltip => New tooltip"`)
- `--dir` — optional, output directory path
- `--no-annotate` — optional flag to skip annotation

**Selector format:** Each selector entry can optionally include a label after `=>`:
- `".my-class"` — highlight with box only (no callout)
- `".my-class => Description of what changed"` — highlight with box AND callout annotation

Convert `$DESCRIPTION` to a kebab-case slug for filenames:
- Lowercase, replace spaces/special chars with hyphens, collapse multiple hyphens
- Store as `$SLUG`

**If no description provided:** Show usage and STOP:
```
Usage: /screenshot <description> [--selectors ".sel1 => Label, .sel2"] [--dir ./path] [--no-annotate]

Examples:
  /screenshot dashboard dark mode --selectors ".widget-header => Restyled header"
  /screenshot eval time column --selectors ".eval-col => Renamed to Eval Time, .tooltip => New tooltip added"
  /screenshot side panel expanded --dir ClientApp/plans/screenshots/3226
  /screenshot login page --no-annotate
```

---

## Step 1: Resolve Session State

### 1.1 Look for Existing Session

Search for `session.json` in this priority order:
1. `$DIR/session.json` (if `--dir` was provided)
2. `./session.json` (cwd)
3. `./screenshots/session.json`

```bash
# Check each location
for p in "${DIR:-.}/session.json" "./session.json" "./screenshots/session.json"; do
  [ -f "$p" ] && echo "$p" && break
done
```

### 1.2 If Session Found

Read the session file and extract:
- `$OUTPUT_DIR` — the output directory
- `$SEQUENCE` — the next sequence number

**If `--dir` was also provided and differs from session dir:** Use `--dir` (explicit flag overrides session).

### 1.3 If No Session Found (First Invocation)

Use **AskUserQuestion** to confirm the output directory:
- Default option: `./screenshots/` (Recommended)
- Second option: `--dir` value if provided, or `./` otherwise
- Let user provide custom path

Store chosen path as `$OUTPUT_DIR`. Set `$SEQUENCE = 0`.

### 1.4 Verify Playwright Is Active

```javascript
// browser_run_code
async (page) => {
  return { url: page.url(), title: await page.title() };
}
```

**If this fails:** STOP and inform user: "No active Playwright browser session. Open a page first with `browser_navigate`."

### 1.5 Create Output Directory

```bash
mkdir -p "$OUTPUT_DIR"
```

---

## Step 2: Ensure annotate.py Exists

### 2.1 Check for Script

```bash
ls "$OUTPUT_DIR/annotate.py" 2>/dev/null
```

### 2.2 If Missing: Write the Script

Write the following Python script verbatim to `$OUTPUT_DIR/annotate.py`:

```python
#!/usr/bin/env python3
"""Annotate screenshots with title overlay and box+callout highlights.

Supports two modes:

1. Legacy CLI (manual box coords):
   python annotate.py input output title x,y,w,h[,label] ...

2. Manifest mode (DOM-sourced rects - recommended):
   python annotate.py --manifest config.json

Manifest JSON format:
{
  "screenshots": [
    {
      "input": "raw-file.png",
      "output": "annotated-file.png",
      "title": "Title overlay text",
      "highlights": [
        {"x": 100, "y": 200, "width": 400, "height": 30, "label": "What this element is"}
      ]
    }
  ]
}

Highlights are drawn as:
1. A rounded-rectangle box around the target element
2. A callout box with label text connected by a line to the target
"""
import sys
import json
import textwrap
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# --- Configuration ---
PADDING = 8
BOX_STROKE = 3
BOX_RADIUS = 8
BANNER_HEIGHT = 48
BANNER_FONT_SIZE = 24
CALLOUT_FONT_SIZE = 15
CALLOUT_MAX_WIDTH = 260
CALLOUT_PADDING_X = 14
CALLOUT_PADDING_Y = 10
CALLOUT_RADIUS = 8
CALLOUT_STROKE = 2
CONNECTOR_GAP = 12

# Colors
HIGHLIGHT_COLOR = (0, 220, 110, 240)
CALLOUT_BORDER = (230, 50, 50, 240)
CALLOUT_FILL = (18, 20, 32, 225)
CONNECTOR_COLOR = (230, 50, 50, 200)
CONNECTOR_WIDTH = 2
BANNER_FILL = (0, 0, 0, 180)
TEXT_COLOR = (255, 255, 255, 255)


def _load_font(size):
    for path in [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def _draw_title(draw, width, title, font):
    draw.rectangle([(0, 0), (width, BANNER_HEIGHT)], fill=BANNER_FILL)
    bbox = draw.textbbox((0, 0), title, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (width - tw) // 2
    ty = (BANNER_HEIGHT - th) // 2
    draw.text((tx, ty), title, fill=TEXT_COLOR, font=font)


def _draw_rounded_rect(draw, rect, color, stroke, radius):
    x1, y1, x2, y2 = rect
    try:
        draw.rounded_rectangle([x1, y1, x2, y2], radius=radius,
                               outline=color, width=stroke)
    except AttributeError:
        draw.rectangle([x1, y1, x2, y2], outline=color, width=stroke)


def _wrap_text(text, font, max_width, draw):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        test = f"{current} {word}".strip()
        bbox = draw.textbbox((0, 0), test, font=font)
        if bbox[2] - bbox[0] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def _compute_callout_rect(target, label_lines, font, draw, img_w, img_h):
    line_height = font.size + 4
    text_h = len(label_lines) * line_height
    text_w = 0
    for line in label_lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        text_w = max(text_w, bbox[2] - bbox[0])
    cw = text_w + CALLOUT_PADDING_X * 2
    ch = text_h + CALLOUT_PADDING_Y * 2

    tx, ty = target["x"], target["y"]
    tw, th = target["width"], target["height"]
    tcx, tcy = tx + tw / 2, ty + th / 2

    # Try right
    cx = tx + tw + PADDING + CONNECTOR_GAP
    cy = tcy - ch / 2
    if cx + cw <= img_w - 10 and cy >= 10 and cy + ch <= img_h - 10:
        return cx, cy, cw, ch, "right"

    # Try left
    cx = tx - PADDING - CONNECTOR_GAP - cw
    cy = tcy - ch / 2
    if cx >= 10 and cy >= 10 and cy + ch <= img_h - 10:
        return cx, cy, cw, ch, "left"

    # Try below
    cx = tcx - cw / 2
    cy = ty + th + PADDING + CONNECTOR_GAP
    cx = max(10, min(cx, img_w - cw - 10))
    if cy + ch <= img_h - 10:
        return cx, cy, cw, ch, "below"

    # Try above
    cx = tcx - cw / 2
    cy = ty - PADDING - CONNECTOR_GAP - ch
    cx = max(10, min(cx, img_w - cw - 10))
    if cy >= 10:
        return cx, cy, cw, ch, "above"

    # Fallback: right side, clamped
    cx = tx + tw + PADDING + CONNECTOR_GAP
    cy = tcy - ch / 2
    cx = max(10, min(cx, img_w - cw - 10))
    cy = max(10, min(cy, img_h - ch - 10))
    return cx, cy, cw, ch, "right"


def _draw_connector(draw, target, callout_rect, direction):
    tx, ty = target["x"], target["y"]
    tw, th = target["width"], target["height"]
    cx, cy, cw, ch = callout_rect

    if direction == "right":
        start = (cx, cy + ch / 2)
        end = (tx + tw + PADDING, ty + th / 2)
    elif direction == "left":
        start = (cx + cw, cy + ch / 2)
        end = (tx - PADDING, ty + th / 2)
    elif direction == "below":
        start = (cx + cw / 2, cy)
        end = (tx + tw / 2, ty + th + PADDING)
    else:
        start = (cx + cw / 2, cy + ch)
        end = (tx + tw / 2, ty - PADDING)

    draw.line([start, end], fill=CONNECTOR_COLOR, width=CONNECTOR_WIDTH)

    # Arrowhead at target end
    import math
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length = math.sqrt(dx * dx + dy * dy)
    if length == 0:
        return
    ux, uy = dx / length, dy / length
    arrow_len = 10
    arrow_w = 5
    base_x = end[0] - ux * arrow_len
    base_y = end[1] - uy * arrow_len
    perp_x, perp_y = -uy, ux
    p1 = (base_x + perp_x * arrow_w, base_y + perp_y * arrow_w)
    p2 = (base_x - perp_x * arrow_w, base_y - perp_y * arrow_w)
    draw.polygon([end, p1, p2], fill=CONNECTOR_COLOR)


def _draw_highlight(draw, h, font, img_w, img_h):
    x, y, w, ht = h["x"], h["y"], h["width"], h["height"]
    box = (x - PADDING, y - PADDING, x + w + PADDING, y + ht + PADDING)
    _draw_rounded_rect(draw, box, HIGHLIGHT_COLOR, BOX_STROKE, BOX_RADIUS)

    label = h.get("label", "").strip()
    if not label:
        return

    lines = _wrap_text(label, font, CALLOUT_MAX_WIDTH, draw)
    if not lines:
        return

    cx, cy, cw, ch, direction = _compute_callout_rect(
        h, lines, font, draw, img_w, img_h
    )

    _draw_rounded_rect(draw, (cx, cy, cx + cw, cy + ch),
                       CALLOUT_BORDER, CALLOUT_STROKE, CALLOUT_RADIUS)
    inner = (cx + CALLOUT_STROKE, cy + CALLOUT_STROKE,
             cx + cw - CALLOUT_STROKE, cy + ch - CALLOUT_STROKE)
    try:
        draw.rounded_rectangle(inner, radius=max(CALLOUT_RADIUS - 2, 0),
                               fill=CALLOUT_FILL)
    except AttributeError:
        draw.rectangle(inner, fill=CALLOUT_FILL)

    _draw_connector(draw, h, (cx, cy, cw, ch), direction)

    line_height = font.size + 4
    text_y = cy + CALLOUT_PADDING_Y
    for line in lines:
        draw.text((cx + CALLOUT_PADDING_X, text_y), line,
                  fill=TEXT_COLOR, font=font)
        text_y += line_height


def annotate(input_path, output_path, title, highlights):
    img = Image.open(input_path).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    title_font = _load_font(BANNER_FONT_SIZE)
    callout_font = _load_font(CALLOUT_FONT_SIZE)

    _draw_title(draw, img.width, title, title_font)

    for h in highlights:
        if isinstance(h, dict):
            _draw_highlight(draw, h, callout_font, img.width, img.height)
        elif isinstance(h, (list, tuple)) and len(h) >= 4:
            rect = {"x": h[0], "y": h[1], "width": h[2], "height": h[3]}
            if len(h) > 4:
                rect["label"] = str(h[4])
            _draw_highlight(draw, rect, callout_font, img.width, img.height)

    result = Image.alpha_composite(img, overlay)
    result.convert("RGB").save(output_path, "PNG")
    print(f"Saved: {output_path}")


def run_manifest(manifest_path):
    manifest_dir = Path(manifest_path).parent
    with open(manifest_path) as f:
        config = json.load(f)

    for entry in config["screenshots"]:
        inp = str(manifest_dir / entry["input"]) if not Path(entry["input"]).is_absolute() else entry["input"]
        out = str(manifest_dir / entry["output"]) if not Path(entry["output"]).is_absolute() else entry["output"]
        annotate(inp, out, entry["title"], entry["highlights"])


if __name__ == "__main__":
    if "--manifest" in sys.argv:
        idx = sys.argv.index("--manifest")
        run_manifest(sys.argv[idx + 1])
    else:
        input_path = sys.argv[1]
        output_path = sys.argv[2]
        title = sys.argv[3]
        highlights = []
        for arg in sys.argv[4:]:
            parts = arg.split(",")
            coords = [int(x) for x in parts[:4]]
            if len(parts) > 4:
                coords.append(",".join(parts[4:]))
            highlights.append(tuple(coords))
        annotate(input_path, output_path, title, highlights)
```

### 2.3 Check PIL Availability

```bash
python3 -c "import PIL" 2>&1
```

**If import fails:** Warn user and set `$NO_ANNOTATE = true`:
```
Pillow not installed. Falling back to raw screenshots only.
Install with: pip3 install Pillow
```

---

## Step 3: Capture Raw Screenshot

### 3.1 Build Filename

```
$RAW_FILENAME = "raw-$NN-$SLUG.png"
```

Where `$NN` is the zero-padded (2-digit) sequence number.

**Examples:**
- `raw-00-dashboard-dark-mode.png`
- `raw-01-eval-time-column.png`

### 3.2 Capture

Use `browser_take_screenshot` with:
- `filename`: `$OUTPUT_DIR/$RAW_FILENAME`
- `type`: `png`

Store the full path as `$RAW_PATH`.

---

## Step 4: Extract DOM Bounding Boxes

**If no `--selectors` provided:** Skip this step. Set `$HIGHLIGHTS = []`.

### 4.1 Parse Selector/Label Pairs

Split the `--selectors` value by commas. For each entry, split on ` => ` to separate the CSS selector from its label:

- `".eval-col => Renamed to Eval Time"` -> selector: `.eval-col`, label: `Renamed to Eval Time`
- `".sidebar"` -> selector: `.sidebar`, label: `""` (empty, box-only)

Store as `$SELECTOR_LABEL_PAIRS`.

### 4.2 Query All Selectors

Use `browser_run_code` to batch-query all selectors in a single call:

```javascript
async (page) => {
  const selectors = ["$SEL1", "$SEL2"];  // CSS selectors only (no labels)
  const results = {};
  for (const sel of selectors) {
    const els = await page.$$(sel);
    const boxes = [];
    for (const el of els) {
      const box = await el.boundingBox();
      if (box) boxes.push(box);
    }
    results[sel] = boxes;
  }
  return results;
}
```

Replace the selectors array with the actual parsed CSS selectors.

### 4.3 Process Results

- Log match counts per selector: `".eval-col": 1 element`
- **Warn** (don't stop) if a selector finds 0 elements: `Warning: ".nonexistent" matched 0 elements`
- Flatten all bounding boxes into a single `$HIGHLIGHTS` array of `{x, y, width, height, label}` objects
- Attach the corresponding label from `$SELECTOR_LABEL_PAIRS` to each bounding box

---

## Step 5: Update manifest.json

### 5.1 Read or Create Manifest

Read `$OUTPUT_DIR/manifest.json`. If it doesn't exist, start with:
```json
{"screenshots": []}
```

### 5.2 Build Annotated Filename

```
$ANNOTATED_FILENAME = "ann-$NN-$SLUG.png"
```

### 5.3 Append Entry

Add to the `screenshots` array:
```json
{
  "input": "$RAW_FILENAME",
  "output": "$ANNOTATED_FILENAME",
  "title": "$NN: $DESCRIPTION",
  "highlights": $HIGHLIGHTS
}
```

Each highlight object includes `{x, y, width, height, label}`. The `label` field may be empty string for box-only highlights.

Note: Use the **bare filenames** (not full paths) since annotate.py resolves relative to the manifest directory.

### 5.4 Write Manifest

Write the updated JSON back to `$OUTPUT_DIR/manifest.json` with 2-space indent.

---

## Step 6: Run annotate.py

**If `$NO_ANNOTATE` is set:** Skip this step and inform user.

```bash
python3 "$OUTPUT_DIR/annotate.py" --manifest "$OUTPUT_DIR/manifest.json"
```

This re-processes ALL manifest entries (idempotent). Each entry's annotated output is regenerated.

**If the command fails:** Warn but do NOT stop. The raw screenshot is preserved.
```
Warning: Annotation failed. Raw screenshot preserved at $RAW_PATH
Error: <stderr output>
```

---

## Step 7: Update session.json

Write the session state to `$OUTPUT_DIR/session.json`:

```json
{
  "dir": "$OUTPUT_DIR",
  "sequence": $NEXT_SEQUENCE,
  "manifest": "$OUTPUT_DIR/manifest.json"
}
```

Where `$NEXT_SEQUENCE = $SEQUENCE + 1`.

---

## Step 8: Summary

Print a concise summary:

```
Screenshot captured

  Description:  $DESCRIPTION
  Raw:          $RAW_PATH
  Annotated:    $OUTPUT_DIR/$ANNOTATED_FILENAME (or "skipped" if --no-annotate)
  Highlights:   $HIGHLIGHT_COUNT element(s) across $SELECTOR_COUNT selector(s)
  Session dir:  $OUTPUT_DIR
  Next seq:     $NEXT_SEQUENCE
```

---

## Error Handling

- **No Playwright session:** STOP immediately with clear instructions
- **Selector misses (0 matches):** Warn but continue -- user still gets the screenshot
- **annotate.py fails:** Warn but continue -- raw screenshot is the fallback
- **PIL not installed:** Auto-set `--no-annotate` and warn with install command
- **File write errors:** STOP and show the error with the path that failed
