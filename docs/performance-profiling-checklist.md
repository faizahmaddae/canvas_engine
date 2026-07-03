# Editor Performance Profiling Checklist

Use this checklist for manual device/emulator profiling after export stress tests pass locally. Record the device, build mode, document scenario, timings, and any visible jank. Prefer profile or release mode for timing decisions; debug mode is useful only for finding obvious correctness issues.

## Test Setup

- Date:
- Tester:
- Device or emulator:
- Android version:
- Build mode: debug / profile / release
- App version or commit:
- Screen size and refresh rate:
- Notes about thermal state or battery saver:

## Documents To Profile

- Empty photo project:
- Typical template project:
- Heavy document: 30+ layers with text, shapes, image masks, opacity, hidden layers, and image effects.
- Large image scenario: one high-resolution imported photo resized smaller on canvas, then adjusted, cropped, and exported.
- Transparent canvas scenario:
- Gradient background scenario:
- Broken image scenario:

## Editor Entry

- Cold app start to Home ready:
- Open editor with empty project:
- Open editor with typical template:
- Open editor with heavy document:
- First frame visually correct: pass / fail
- Any blank canvas, late asset pop-in, or loading stall:

## Canvas Interaction

- Pan and zoom smoothness on empty project: pass / fail
- Pan and zoom smoothness on heavy document: pass / fail
- Select layer latency:
- Drag selected layer smoothness:
- Resize selected layer smoothness:
- Rotate selected layer smoothness:
- Multi-select drag smoothness:
- Layer actions sheet open time:
- Layers drawer open and scroll smoothness:

## Image And Crop

- Import large image time:
- Large image preview memory behavior:
- Image filter panel open time:
- Image adjustment slider smoothness:
- Crop mode entry time:
- Crop frame drag smoothness:
- Crop commit time:
- Restore image action time:
- Broken image placeholder visible and recoverable: pass / fail

## Save And Export

- Manual Save time with typical document:
- Manual Save time with heavy document:
- PNG export time at default size:
- PNG export time at fixed large preset:
- JPG export time at default size:
- JPG export time at fixed large preset:
- Export preview appears with correct pixels: pass / fail
- Transparent PNG alpha preserved: pass / fail
- JPG flatten background correct: pass / fail
- Oversized export request reduces resolution instead of crashing: pass / fail

## Memory Observations

- Baseline memory on Home:
- Memory after editor open:
- Memory after large image import:
- Memory during crop mode:
- Peak memory during PNG export:
- Peak memory during JPG export:
- Memory after returning to Home:
- Repeated export memory returns near baseline: pass / fail
- Any low-memory warnings, process kills, or visible stalls:

## Pass/Fail Notes

- Overall pass/fail:
- Highest-risk finding:
- Reproduction steps:
- Screenshots or screen recordings captured:
- Follow-up issue or task: