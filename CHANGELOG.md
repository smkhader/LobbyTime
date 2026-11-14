# Changelog

All notable LobbyTime changes are documented here.

## 3.7.5

### Added

- Windows Forms graphical configuration interface.
- Live display preview with current Time and Date.
- Preview sizing based on the primary display aspect ratio.
- Current Windows wallpaper detection and import.
- Browse Image support for JPG and PNG backgrounds.
- Solid-color background selection.
- Independent Time and Date font configuration.
- Native Windows font chooser.
- Independent font family, style, and size for Time and Date.
- Font color selection.
- Overlay opacity control.
- Friendly Text Shadow presets: None, Soft, Medium, and Strong.
- Selectable and copyable Activity Log.
- Normal Microsoft Edge launch mode.
- Full-screen Microsoft Edge kiosk launch mode.
- Configuration schema versioning and normalization.
- Local `assets` folder for imported backgrounds.

### Changed

- Replaced the original console-oriented configuration workflow with a Windows Forms GUI.
- Simplified font configuration around the native Windows font dialog.
- Consolidated background controls into a single button row.
- Improved configuration-window spacing and alignment.
- Changed the configuration window to a fixed layout for consistent rendering.
- Improved preview sizing for different display aspect ratios.
- Improved Time and Date positioning within the preview.
- Added tabular clock numerals to reduce visible movement when digits change.
- Improved background image handling and browser cache refresh behavior.
- Improved generated HTML structure and styling.
- Improved configuration migration from older LobbyTime versions.
- Simplified Text Shadow configuration so CSS values no longer need to be entered manually.

### Fixed

- Fixed malformed background URL interpolation in generated HTML.
- Fixed kiosk launching after removal of the original custom font selector.
- Fixed Graphics.DrawString overload errors during WinForms redraw operations.
- Fixed owner-drawn font selector errors triggered by window repainting.
- Fixed font-resource disposal that could cause controls to render as red-X error boxes.
- Fixed repeated errors during window resize and repaint.
- Fixed preview aspect-ratio issues.
- Fixed wallpaper controls disappearing during layout changes.
- Fixed current-wallpaper discovery and import behavior.
- Fixed several GUI spacing, alignment, and unused-space problems.

## Previous Versions

Earlier LobbyTime releases used a primarily console-based configuration workflow.

Version 3.7.5 represents the transition to the current graphical configuration and live-preview architecture.
