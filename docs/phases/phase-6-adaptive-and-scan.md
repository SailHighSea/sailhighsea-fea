# Phase 6: Adaptive layouts and receipt scan (weeks 10 to 12)

**Status:** Done on this branch (see CHANGELOG.md, Phase 6). Not run on real hardware: camera and ML Kit read, Supabase Storage upload, a real foldable, Windows and macOS window limits.

## Do
1. Audit every screen at widths 360, 600, 840, 1024, 1280, 1920 and in the fold half-open state. Fix gaps against the mockups. Verify the feature parity rule: every action available on phone exists on tablet and desktop.
2. Fold support: hinge detection, half-open Home (see Fold mockup) and Add form below the hinge, state preserved across fold/unfold.
3. Desktop polish: keyboard navigation, focus rings, shortcuts, window min size, context menus, mouse hover states.
4. Receipt scan (Scan mockup): mobile camera with on-device recognition; desktop webcam or file picker. Pre-fill Add form. Store receipt image in Supabase Storage with RLS.
5. Integration tests across sizes. Build to `test/` and report.
