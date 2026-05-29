# AI UI Review Instructions

## For the AI reviewer (read_image each screenshot):

### Visual Checklist (per screenshot):
1. **Background**: Is it `#0E1416` (cool dark teal-black)? Not pure black.
2. **Text color**: Is primary text `#DDE4E5`? Not pure white.
3. **Accent color**: Is interactive accent Cyan `#8AEBFF`? Not blue/purple.
4. **Waveform**: Is it Coral `#FF6B5F`? The signature color.
5. **Borders**: Are they subtle `#3C494C`? Not bright.
6. **Font**: System font (SF Pro)? Numbers monospaced?
7. **Spacing**: 8px grid rhythm? Consistent padding?
8. **Record button**: Red circle, prominent, with glow when active?
9. **Status bar**: Compact, monospaced data, bottom of window?
10. **Information density**: Dense but not cluttered?

### Interaction Checklist (comparing before/after screenshots):
1. **State transition**: Is the visual change clear between states?
2. **Button feedback**: Did the button visually respond?
3. **Status update**: Did status bar text change appropriately?
4. **Waveform**: Did it start/stop scrolling?
5. **Level meter**: Did it respond to audio?
6. **No UI glitches**: No overlapping, no truncation, no misalignment?

### Design System Violations to Flag:
- Pure white (#FFFFFF) text
- Pure black (#000000) background
- Emoji as UI elements (should be SF Symbols)
- Rounded corners > 16px (except record button)
- Decorative gradients
- Center-aligned body text
- Card with colored left border pattern
