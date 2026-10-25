# LobbyTime v2.3

A small PowerShell lobby clock that generates `kiosk.html` and can launch Microsoft Edge in kiosk or normal mode.

## Included
- `LobbyTime.ps1` - main script
- `kiosk-config.json` - default settings
- `Start-Kiosk.bat` - launches LobbyTime in Edge kiosk mode

`kiosk.html` and the selected `background.jpg` or `background.png` are generated at runtime.

## Run
Double-click `Start-Kiosk.bat` for kiosk mode, or run:

    powershell.exe -ExecutionPolicy Bypass -File .\LobbyTime.ps1

## Background fix
Windows wallpapers are discovered using the PowerShell file object's `FullName` property. A selected PNG/JPEG is validated and copied next to the generated HTML as `background.png` or `background.jpg`.

The background menu now has one Solid Color entry, with presets and a custom hex option under it.
