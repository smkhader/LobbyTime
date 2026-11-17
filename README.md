# LobbyTime

LobbyTime is a self-contained PowerShell utility for creating and displaying a customizable lobby clock in Microsoft Edge.

## Current Version

**LobbyTime 3.7.5**

Version 3.7.5 introduces a Windows Forms configuration interface, live display preview, improved Windows wallpaper support, independent time and date font controls, and a cleaner kiosk workflow.

## Features

- Windows Forms graphical configuration interface
- Live clock and background preview
- Preview adapted to the primary display aspect ratio
- Custom JPG and PNG backgrounds
- Import the current Windows wallpaper
- Solid-color backgrounds
- Independent Time and Date font selection
- Native Windows font chooser
- Font color configuration
- Overlay opacity control
- Configurable time and date formats
- Simplified text-shadow presets
- Selectable and copyable Activity Log
- Normal Microsoft Edge launch mode
- Full-screen Microsoft Edge kiosk mode
- JSON configuration storage
- Automatic configuration migration
- Generated single-page HTML display
- Tabular clock numerals for more stable digit spacing

## Requirements

- Windows
- Windows PowerShell
- Microsoft Edge
- .NET Windows Forms and System.Drawing

## Getting Started

Open PowerShell in the LobbyTime folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\LobbyTime.ps1
```

The graphical configuration interface opens by default.

## Background Configuration

LobbyTime provides four background controls:

- **Browse Image...** selects a JPG or PNG image.
- **Use Current Wallpaper** imports the current Windows desktop wallpaper.
- **Solid Color...** selects a solid background color.
- **Clear Image** removes the configured background image.

Imported background images are stored in the local `assets` folder.

The live preview reflects the selected background and approximates the aspect ratio of the primary display.

## Clock and Appearance

Time and Date can use independent fonts.

Select **Choose...** beside either font to open the native Windows font chooser.

The font chooser controls the font family, style, and size.

Additional appearance controls include:

- Font color
- Overlay opacity
- Time format
- Date format
- Text shadow

### Text Shadow

Text shadow has four simplified presets:

- **None**
- **Soft**
- **Medium**
- **Strong**

LobbyTime converts these presets into the appropriate display styling automatically.

## Time Formats

Examples include:

```text
hh:mm A
hh:mm:ss A
HH:mm
HH:mm:ss
```

## Date Formats

Examples include:

```text
dddd, MMMM D, YYYY
ddd, MMM D, YYYY
MM/DD/YYYY
MMMM D
```

## Activity Log

LobbyTime includes a running Activity Log for configuration and launch operations.

The log is read-only but selectable.

Use **Ctrl+C** to copy selected log entries.

## Save and Launch Controls

### Save & Refresh HTML

Saves the current configuration and regenerates `kiosk.html`.

### Launch Normal

Generates the current display and opens it in Microsoft Edge normal mode.

### Launch Kiosk

Generates the current display and launches Microsoft Edge in full-screen kiosk mode.

### Reset Defaults

Restores the default LobbyTime configuration.

## Command-Line Usage

LobbyTime also supports command-line actions:

```powershell
.\LobbyTime.ps1 -Action gui
.\LobbyTime.ps1 -Action create
.\LobbyTime.ps1 -Action normal
.\LobbyTime.ps1 -Action kiosk
```

`gui` is the default action.

### gui

Opens the graphical configuration interface.

### create

Generates `kiosk.html` without launching Microsoft Edge.

### normal

Generates the display and opens it in Microsoft Edge normal mode.

### kiosk

Generates the display and launches Microsoft Edge in kiosk mode.

## Files

```text
LobbyTime.ps1
kiosk-config.json
kiosk.html
README.md
CHANGELOG.md
LICENSE
assets\
```

### LobbyTime.ps1

Main LobbyTime application.

### kiosk-config.json

Stores the current LobbyTime configuration.

Version 3.7.5 uses configuration schema version 4 and normalizes older configuration values when loaded.

### kiosk.html

Generated single-page lobby display used by Microsoft Edge.

### assets

Stores imported background images.

## Development Progress

LobbyTime began as a console-oriented PowerShell utility and has evolved into a graphical Windows configuration application.

The 3.7.x development cycle focused heavily on:

- Live preview rendering
- Windows wallpaper importing
- Display aspect-ratio handling
- Native font selection
- Independent Time and Date appearance
- Stable clock-number spacing
- GUI layout and spacing
- WinForms redraw reliability
- Simplified text-shadow controls
- Activity logging
- Kiosk-launch reliability
- Configuration compatibility and migration

See `CHANGELOG.md` for release details.

## License

See `LICENSE`.
