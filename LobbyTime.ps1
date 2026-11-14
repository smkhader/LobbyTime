<#
.SYNOPSIS
    LobbyTime GUI v3.7.5 - configurable lobby clock for Microsoft Edge.
.DESCRIPTION
    Windows Forms configuration UI with a 16:9 live preview, reliable current-wallpaper
    import, stable-width clock numerals, and configuration stored beside this script.
#>
[CmdletBinding()]
param(
    [ValidateSet('gui','create','normal','kiosk')]
    [string]$Action = 'gui'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$script:AppVersion='3.7.5'
$script:SchemaVersion=4
$script:ScriptFolder=Split-Path -Parent $PSCommandPath
$script:ConfigPath=Join-Path $script:ScriptFolder 'kiosk-config.json'
$script:HtmlPath=Join-Path $script:ScriptFolder 'kiosk.html'
$script:AssetsFolder=Join-Path $script:ScriptFolder 'assets'
$script:Config=$null

function Get-DefaultConfig {
    [ordered]@{
        SchemaVersion=$script:SchemaVersion
        BackgroundFileName=''
        BackgroundColor='#0B1220'
        OverlayOpacity=0.18
        TimeFontSize='9vw'
        DateFontSize='3vw'
        FontFamily='Segoe UI, Arial, sans-serif'
        TimeFontFamily='Segoe UI'
        TimeFontStyle='Regular'
        DateFontFamily='Segoe UI'
        DateFontStyle='Regular'
        FontColor='#FFFFFF'
        TextShadow='0 2px 6px rgba(0,0,0,0.60)'
        TimeFormat='hh:mm:ss A'
        DateFormat='dddd, MMMM D, YYYY'
    }
}

function ConvertTo-CanonicalConfig {
    param([object]$InputConfig)
    $defaults=Get-DefaultConfig
    $result=[ordered]@{}
    foreach($name in $defaults.Keys){
        $value=$defaults[$name]
        if($null -ne $InputConfig -and $null -ne $InputConfig.PSObject.Properties[$name]){
            $candidate=$InputConfig.$name
            if($null -ne $candidate){$value=$candidate}
        }
        $result[$name]=$value
    }
    $result.SchemaVersion=$script:SchemaVersion
    if([string]::IsNullOrWhiteSpace([string]$result.BackgroundColor) -or [string]$result.BackgroundColor -notmatch '^#[0-9A-Fa-f]{6}$'){$result.BackgroundColor='#0B1220'}else{$result.BackgroundColor=([string]$result.BackgroundColor).ToUpperInvariant()}
    if([string]$result.FontColor -notmatch '^#[0-9A-Fa-f]{6}$'){$result.FontColor='#FFFFFF'}else{$result.FontColor=([string]$result.FontColor).ToUpperInvariant()}
    try{$opacity=[double]$result.OverlayOpacity}catch{$opacity=0.18}
    $result.OverlayOpacity=[Math]::Round([Math]::Max(0.0,[Math]::Min(0.85,$opacity)),2)
    foreach($name in 'TimeFontSize','DateFontSize','FontFamily','TimeFontFamily','TimeFontStyle','DateFontFamily','DateFontStyle','TextShadow','TimeFormat','DateFormat'){
        if([string]::IsNullOrWhiteSpace([string]$result[$name])){$result[$name]=$defaults[$name]}
    }
    $legacyFamily=(([string]$result.FontFamily -split ',')[0]).Trim().Trim([char]39).Trim([char]34)
    if([string]::IsNullOrWhiteSpace([string]$result.TimeFontFamily)){$result.TimeFontFamily=$legacyFamily}
    if([string]::IsNullOrWhiteSpace([string]$result.DateFontFamily)){$result.DateFontFamily=$legacyFamily}
    $result.BackgroundFileName=[string]$result.BackgroundFileName
    [pscustomobject]$result
}

function Save-Config {
    param([object]$Config)
    $canonical=ConvertTo-CanonicalConfig $Config
    $json=$canonical|ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($script:ConfigPath,$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $script:Config=$canonical
}

function Load-Config {
    if(-not(Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)){
        $config=ConvertTo-CanonicalConfig $null
        Save-Config $config
        return $script:Config
    }
    try{
        $raw=Get-Content -LiteralPath $script:ConfigPath -Raw
        $normalized=ConvertTo-CanonicalConfig ($raw|ConvertFrom-Json)
        $normalizedJson=$normalized|ConvertTo-Json -Depth 4
        if($raw.Trim() -ne $normalizedJson.Trim()){
            $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
            Copy-Item -LiteralPath $script:ConfigPath -Destination "$($script:ConfigPath).pre-v3-$stamp.bak" -Force
            Save-Config $normalized
        }
        return $normalized
    }catch{
        $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $script:ConfigPath -Destination "$($script:ConfigPath).invalid-$stamp.bak" -Force -ErrorAction SilentlyContinue
        $config=ConvertTo-CanonicalConfig $null
        Save-Config $config
        return $script:Config
    }
}

function ConvertTo-HtmlText { param([AllowNull()][string]$Text) if($null -eq $Text){return ''}; [Net.WebUtility]::HtmlEncode($Text) }
function ConvertTo-JavaScriptString { param([AllowNull()][string]$Text) if($null -eq $Text){return ''}; $Text.Replace('\','\\').Replace("'","\'").Replace("`r",'').Replace("`n",'\n') }

function Resolve-BackgroundPath {
    param([object]$Config)
    $name=[string]$Config.BackgroundFileName
    if([string]::IsNullOrWhiteSpace($name)){return $null}
    if([IO.Path]::IsPathRooted($name)){$candidate=$name}else{$candidate=Join-Path $script:ScriptFolder $name}
    if(Test-Path -LiteralPath $candidate -PathType Leaf){return (Get-Item -LiteralPath $candidate).FullName}
    return $null
}

function Test-ImageFile {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try{$bytes=New-Object byte[] 8;$read=$stream.Read($bytes,0,8)}finally{$stream.Dispose()}
        if($read -ge 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47){return 'png'}
        if($read -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8){return 'jpg'}
    }catch{}
    return $null
}

function Import-BackgroundImage {
    param([string]$SourcePath)
    $extension=Test-ImageFile $SourcePath
    if(-not $extension){throw 'The selected file is not a valid PNG or JPEG image.'}
    if(-not(Test-Path -LiteralPath $script:AssetsFolder)){New-Item -Path $script:AssetsFolder -ItemType Directory -Force|Out-Null}
    $destination=Join-Path $script:AssetsFolder "background.$extension"
    if([IO.Path]::GetFullPath($SourcePath) -ne [IO.Path]::GetFullPath($destination)){Copy-Item -LiteralPath $SourcePath -Destination $destination -Force}
    foreach($oldName in 'background.jpg','background.png'){
        $oldPath=Join-Path $script:AssetsFolder $oldName
        if($oldPath -ne $destination){Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue}
    }
    'assets/'+[IO.Path]::GetFileName($destination)
}

function Get-CurrentWindowsWallpaper {
    [CmdletBinding()]param()
    $candidates=[Collections.Generic.List[string]]::new()
    try{
        if(-not('LobbyTime.NativeWallpaper' -as [type])){
            Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace LobbyTime { public static class NativeWallpaper {
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern bool SystemParametersInfo(uint uiAction,uint uiParam,StringBuilder pvParam,uint fWinIni);
}}
"@
        }
        $buffer=New-Object Text.StringBuilder 32768
        if([LobbyTime.NativeWallpaper]::SystemParametersInfo(0x0073,$buffer.Capacity,$buffer,0) -and -not[string]::IsNullOrWhiteSpace($buffer.ToString())){[void]$candidates.Add([Environment]::ExpandEnvironmentVariables($buffer.ToString()))}
    }catch{}
    foreach($entry in @(
        @('HKCU:\Control Panel\Desktop','Wallpaper'),
        @('HKCU:\Software\Microsoft\Internet Explorer\Desktop\General','WallpaperSource')
    )){
        try{$value=[string](Get-ItemProperty -LiteralPath $entry[0] -ErrorAction Stop).($entry[1]);if(-not[string]::IsNullOrWhiteSpace($value)){[void]$candidates.Add([Environment]::ExpandEnvironmentVariables($value))}}catch{}
    }
    try{
        $history=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -ErrorAction Stop
        foreach($property in 'BackgroundHistoryPath0','BackgroundHistoryPath1','BackgroundHistoryPath2','BackgroundHistoryPath3','BackgroundHistoryPath4'){$value=[string]$history.$property;if(-not[string]::IsNullOrWhiteSpace($value)){[void]$candidates.Add([Environment]::ExpandEnvironmentVariables($value))}}
    }catch{}
    $themes=Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    [void]$candidates.Add((Join-Path $themes 'TranscodedWallpaper'))
    $cached=Join-Path $themes 'CachedFiles'
    if(Test-Path -LiteralPath $cached -PathType Container){Get-ChildItem -LiteralPath $cached -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|ForEach-Object{[void]$candidates.Add($_.FullName)}}
    foreach($candidate in ($candidates|Select-Object -Unique)){
        if([string]::IsNullOrWhiteSpace([string]$candidate) -or -not(Test-Path -LiteralPath $candidate -PathType Leaf)){continue}
        $kind=Test-ImageFile $candidate
        if(-not $kind){continue}
        $extension=[IO.Path]::GetExtension($candidate).ToLowerInvariant()
        if($extension -in '.jpg','.jpeg','.png'){return (Get-Item -LiteralPath $candidate).FullName}
        $temp=Join-Path $env:TEMP "LobbyTime-CurrentWallpaper.$kind"
        Copy-Item -LiteralPath $candidate -Destination $temp -Force
        return $temp
    }
    return $null
}

function Get-BackgroundCss {
    param([object]$Config)
    $color=[string]$Config.BackgroundColor;if($color -notmatch '^#[0-9A-Fa-f]{6}$'){$color='#0B1220'}
    $css="background-color:$color;";$path=Resolve-BackgroundPath $Config
    if($path){
        $relative=[string]$Config.BackgroundFileName
        if([IO.Path]::IsPathRooted($relative)){$uri=([Uri]$path).AbsoluteUri}else{$uri=(($relative.Replace('\','/').Split('/')|ForEach-Object{[Uri]::EscapeDataString($_)}) -join '/')}
        $stamp=(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        $css+="background-image:url('${uri}?v=$stamp');background-position:center;background-size:cover;background-repeat:no-repeat;"
    }
    $css
}

function New-LobbyHtml {
    param([object]$Config)
    $Config=ConvertTo-CanonicalConfig $Config
    $backgroundCss=Get-BackgroundCss $Config
    $fontFamily=ConvertTo-HtmlText ([string]$Config.FontFamily);$timeFontFamily=ConvertTo-HtmlText ([string]$Config.TimeFontFamily);$dateFontFamily=ConvertTo-HtmlText ([string]$Config.DateFontFamily);$timeFontStyle=ConvertTo-HtmlText ([string]$Config.TimeFontStyle);$dateFontStyle=ConvertTo-HtmlText ([string]$Config.DateFontStyle);$fontColor=ConvertTo-HtmlText ([string]$Config.FontColor)
    $timeSize=ConvertTo-HtmlText ([string]$Config.TimeFontSize);$dateSize=ConvertTo-HtmlText ([string]$Config.DateFontSize)
    $shadow=ConvertTo-HtmlText ([string]$Config.TextShadow);$timeFormat=ConvertTo-JavaScriptString ([string]$Config.TimeFormat);$dateFormat=ConvertTo-JavaScriptString ([string]$Config.DateFormat)
    $opacity=[string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0:0.00}',[double]$Config.OverlayOpacity)
    $html=@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LobbyTime</title>
<style>html,body{height:100%;margin:0;overflow:hidden}body{display:flex;align-items:center;justify-content:center;color:$fontColor;font-family:$fontFamily;$backgroundCss}.overlay{position:fixed;inset:0;background:rgba(0,0,0,$opacity);pointer-events:none}.container{position:relative;text-align:center;width:100%;padding:1rem;box-sizing:border-box}.time{font-family:'$timeFontFamily',Arial,sans-serif;font-size:$timeSize;font-style:normal;font-weight:600;letter-spacing:2px;text-shadow:$shadow;font-variant-numeric:tabular-nums;font-feature-settings:"tnum" 1}.date{font-family:'$dateFontFamily',Arial,sans-serif;font-size:$dateSize;font-style:normal;margin-top:.5rem;opacity:.95;text-shadow:$shadow}</style></head>
<body><div class="overlay"></div><div class="container"><div class="time" id="time">--:--</div><div class="date" id="date">Loading...</div></div>
<script>function pad(n){return n.toString().padStart(2,'0')}function fmt(d,f){var mn=['January','February','March','April','May','June','July','August','September','October','November','December'],ms=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'],wn=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'],ws=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];return f.replace(/YYYY|YY|MMMM|MMM|MM|M|DD|D|dddd|ddd|HH|hh|mm|ss|A/g,function(t){switch(t){case'YYYY':return d.getFullYear();case'YY':return String(d.getFullYear()).slice(-2);case'MMMM':return mn[d.getMonth()];case'MMM':return ms[d.getMonth()];case'MM':return pad(d.getMonth()+1);case'M':return d.getMonth()+1;case'DD':return pad(d.getDate());case'D':return d.getDate();case'dddd':return wn[d.getDay()];case'ddd':return ws[d.getDay()];case'HH':return pad(d.getHours());case'hh':var h=d.getHours()%12;return pad(h===0?12:h);case'mm':return pad(d.getMinutes());case'ss':return pad(d.getSeconds());case'A':return d.getHours()>=12?'PM':'AM'}})}var tf='$timeFormat',df='$dateFormat';function update(){var d=new Date();document.getElementById('time').textContent=fmt(d,tf);document.getElementById('date').textContent=fmt(d,df)}update();setInterval(update,1000);</script></body></html>
"@
    [IO.File]::WriteAllText($script:HtmlPath,$html,[Text.UTF8Encoding]::new($false));$script:HtmlPath
}

function Find-Edge { foreach($candidate in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe","$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")){if($candidate -and(Test-Path -LiteralPath $candidate -PathType Leaf)){return $candidate}};$command=Get-Command msedge.exe -ErrorAction SilentlyContinue;if($command){return $command.Source};$null }
function Start-LobbyEdge { param([object]$Config,[switch]$Kiosk) Save-Config $Config;$html=New-LobbyHtml $script:Config;$edge=Find-Edge;if(-not$edge){throw 'Microsoft Edge could not be found.'};$uri=([Uri]$html).AbsoluteUri;if($Kiosk){Start-Process -FilePath $edge -ArgumentList @('--kiosk',$uri,'--edge-kiosk-type=fullscreen','--no-first-run')}else{Start-Process -FilePath $edge -ArgumentList @('--start-maximized','--no-first-run',$uri)} }
function Show-ColorDialog { param([string]$InitialColor) $dialog=New-Object Windows.Forms.ColorDialog;$dialog.FullOpen=$true;try{$dialog.Color=[Drawing.ColorTranslator]::FromHtml($InitialColor)}catch{};if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return('#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B)};$null }

function Show-LobbyTimeGui {
    $script:Config=Load-Config
    $form=New-Object Windows.Forms.Form;$form.Text="LobbyTime $($script:AppVersion)";$form.StartPosition='CenterScreen';$form.ClientSize=New-Object Drawing.Size(1040,540);$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false;$form.Font=New-Object Drawing.Font('Segoe UI',9)
    $main=New-Object Windows.Forms.TableLayoutPanel;$main.Dock='Fill';$main.Padding=New-Object Windows.Forms.Padding(12,8,12,6);$main.ColumnCount=2;$main.RowCount=2
    [void]$main.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',46)));[void]$main.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',54)));[void]$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',52)));$form.Controls.Add($main)
    $primaryBounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds
    $screenAspect=if($primaryBounds.Height -gt 0){$primaryBounds.Width/[double]$primaryBounds.Height}else{16.0/9.0}
    $previewRowWidth=500
    $previewRowHeight=[int][Math]::Round($previewRowWidth/$screenAspect)
    $previewRowHeight=[Math]::Max(220,[Math]::Min(300,$previewRowHeight))

    $left=New-Object Windows.Forms.GroupBox;$left.Text='Background';$left.Dock='Fill';$left.Padding=New-Object Windows.Forms.Padding(12,10,12,12);$left.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Regular);$main.Controls.Add($left,0,0)
    $leftLayout=New-Object Windows.Forms.TableLayoutPanel;$leftLayout.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular);$leftLayout.Dock='Top';$leftLayout.Height=$previewRowHeight+48;$leftLayout.ColumnCount=1;$leftLayout.RowCount=2;[void]$leftLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$previewRowHeight)));[void]$leftLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',48)));$left.Controls.Add($leftLayout)

    $previewHost=New-Object Windows.Forms.Panel;$previewHost.Dock='Fill';$previewHost.BackColor=[Drawing.Color]::FromArgb(28,28,28);$previewHost.Margin=New-Object Windows.Forms.Padding(0)
    $preview=New-Object Windows.Forms.PictureBox;$preview.Dock='Fill';$preview.SizeMode='Zoom';$preview.BackColor=[Drawing.Color]::FromArgb(11,18,32);$preview.BorderStyle='FixedSingle';$previewHost.Controls.Add($preview);$leftLayout.Controls.Add($previewHost,0,0)

    $backgroundButtons=New-Object Windows.Forms.FlowLayoutPanel;$backgroundButtons.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular);$backgroundButtons.Dock='Fill';$backgroundButtons.FlowDirection='LeftToRight';$backgroundButtons.WrapContents=$false;$backgroundButtons.Padding=New-Object Windows.Forms.Padding(0,5,0,0)
    $btnBrowse=New-Object Windows.Forms.Button;$btnBrowse.Text='Browse Image...';$btnBrowse.AutoSize=$true
    $btnWallpaper=New-Object Windows.Forms.Button;$btnWallpaper.Text='Use Current Wallpaper';$btnWallpaper.AutoSize=$true
    $btnColor=New-Object Windows.Forms.Button;$btnColor.Text='Solid Color...';$btnColor.AutoSize=$true
    $btnClear=New-Object Windows.Forms.Button;$btnClear.Text='Clear Image';$btnClear.AutoSize=$true
    foreach($button in @($btnBrowse,$btnWallpaper,$btnColor,$btnClear)){$button.Margin=New-Object Windows.Forms.Padding(3,2,3,2)}
    $backgroundButtons.Controls.AddRange(@($btnBrowse,$btnWallpaper,$btnColor,$btnClear));$leftLayout.Controls.Add($backgroundButtons,0,1)
    $lblBackground=New-Object Windows.Forms.Label;$lblBackground.Visible=$false

    $right=New-Object Windows.Forms.GroupBox;$right.Text='Clock and appearance';$right.Dock='Fill';$right.Padding=New-Object Windows.Forms.Padding(14,10,14,12);$right.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Regular);$main.Controls.Add($right,1,0)
    $settings=New-Object Windows.Forms.TableLayoutPanel;$settings.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular);$settings.Dock='Top';$settings.AutoSize=$false;$settings.Height=286;$settings.ColumnCount=2;$settings.RowCount=7;$settings.Padding=New-Object Windows.Forms.Padding(0,8,0,4);[void]$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',126)));[void]$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));for($i=0;$i -lt 7;$i++){[void]$settings.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',40)))};$right.Controls.Add($settings)
    function Add-SettingRow([int]$row,[string]$label,[Windows.Forms.Control]$control){$l=New-Object Windows.Forms.Label;$l.Text=$label;$l.Dock='Fill';$l.TextAlign='MiddleRight';$l.Margin=New-Object Windows.Forms.Padding(0,4,10,4);$control.Dock='Fill';$control.Margin=New-Object Windows.Forms.Padding(0,5,0,5);$settings.Controls.Add($l,0,$row);$settings.Controls.Add($control,1,$row)}
    $txtTimeFont=New-Object Windows.Forms.TextBox;$txtTimeFont.ReadOnly=$true;$txtTimeFont.BackColor=[Drawing.SystemColors]::Window
    $btnTimeFont=New-Object Windows.Forms.Button;$btnTimeFont.Text='Choose...';$btnTimeFont.Width=92
    $timeFontPanel=New-Object Windows.Forms.TableLayoutPanel;$timeFontPanel.ColumnCount=2;$timeFontPanel.RowCount=1;$timeFontPanel.Dock='Fill';$timeFontPanel.Margin=New-Object Windows.Forms.Padding(0);[void]$timeFontPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$timeFontPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',92)));$timeFontPanel.Controls.Add($txtTimeFont,0,0);$timeFontPanel.Controls.Add($btnTimeFont,1,0)
    $txtDateFont=New-Object Windows.Forms.TextBox;$txtDateFont.ReadOnly=$true;$txtDateFont.BackColor=[Drawing.SystemColors]::Window
    $btnDateFont=New-Object Windows.Forms.Button;$btnDateFont.Text='Choose...';$btnDateFont.Width=92
    $dateFontPanel=New-Object Windows.Forms.TableLayoutPanel;$dateFontPanel.ColumnCount=2;$dateFontPanel.RowCount=1;$dateFontPanel.Dock='Fill';$dateFontPanel.Margin=New-Object Windows.Forms.Padding(0);[void]$dateFontPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$dateFontPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',92)));$dateFontPanel.Controls.Add($txtDateFont,0,0);$dateFontPanel.Controls.Add($btnDateFont,1,0)
    $txtFontColor=New-Object Windows.Forms.TextBox;$btnFontColor=New-Object Windows.Forms.Button;$btnFontColor.Text='Choose...';$btnFontColor.Width=92
    $fontColorPanel=New-Object Windows.Forms.TableLayoutPanel;$fontColorPanel.ColumnCount=2;$fontColorPanel.RowCount=1;$fontColorPanel.Dock='Fill';$fontColorPanel.Margin=New-Object Windows.Forms.Padding(0);[void]$fontColorPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$fontColorPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',90)));$fontColorPanel.Controls.Add($txtFontColor,0,0);$fontColorPanel.Controls.Add($btnFontColor,1,0)
    $nudOpacity=New-Object Windows.Forms.NumericUpDown;$nudOpacity.DecimalPlaces=2;$nudOpacity.Increment=0.05;$nudOpacity.Minimum=0;$nudOpacity.Maximum=0.85
    $cmbTimeFormat=New-Object Windows.Forms.ComboBox;$cmbTimeFormat.DropDownStyle='DropDown';[void]$cmbTimeFormat.Items.AddRange(@('hh:mm A','hh:mm:ss A','HH:mm','HH:mm:ss'))
    $cmbDateFormat=New-Object Windows.Forms.ComboBox;$cmbDateFormat.DropDownStyle='DropDown';[void]$cmbDateFormat.Items.AddRange(@('dddd, MMMM D, YYYY','ddd, MMM D, YYYY','MM/DD/YYYY','MMMM D'))
    $cmbShadow=New-Object Windows.Forms.ComboBox;$cmbShadow.DropDownStyle='DropDownList';[void]$cmbShadow.Items.AddRange(@('None','Soft','Medium','Strong'))
    Add-SettingRow 0 'Time font' $timeFontPanel;Add-SettingRow 1 'Date font' $dateFontPanel;Add-SettingRow 2 'Font color' $fontColorPanel;Add-SettingRow 3 'Overlay opacity' $nudOpacity;Add-SettingRow 4 'Time format' $cmbTimeFormat;Add-SettingRow 5 'Date format' $cmbDateFormat;Add-SettingRow 6 'Text shadow' $cmbShadow
    $status=New-Object Windows.Forms.Label;$status.Text='Ready';$status.Visible=$false

    $logGroup=New-Object Windows.Forms.GroupBox;$logGroup.Text='Activity Log';$logGroup.Dock='Top';$logGroup.Height=112;$logGroup.Margin=New-Object Windows.Forms.Padding(0);$logGroup.Padding=New-Object Windows.Forms.Padding(8,6,8,8);$logGroup.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Regular)
    $right.Controls.Add($logGroup);$logGroup.BringToFront()
    $logBox=New-Object Windows.Forms.TextBox;$logBox.Multiline=$true;$logBox.ReadOnly=$true;$logBox.ScrollBars='Vertical';$logBox.Dock='Fill';$logBox.WordWrap=$false;$logBox.Font=New-Object Drawing.Font('Consolas',9,[Drawing.FontStyle]::Regular);$logBox.BackColor=[Drawing.SystemColors]::Window;$logBox.ShortcutsEnabled=$true
    $logGroup.Controls.Add($logBox)
    function Add-Log([string]$message){$line='[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$message;if($logBox.TextLength -gt 0){$logBox.AppendText([Environment]::NewLine)};$logBox.AppendText($line);$logBox.SelectionStart=$logBox.TextLength;$logBox.ScrollToCaret();$status.Text=$message}

    $actions=New-Object Windows.Forms.FlowLayoutPanel;$actions.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular);$actions.Dock='Fill';$actions.FlowDirection='RightToLeft';$actions.WrapContents=$false;$actions.Padding=New-Object Windows.Forms.Padding(0,8,0,0);$actions.Margin=New-Object Windows.Forms.Padding(0);$main.SetColumnSpan($actions,2);$main.Controls.Add($actions,0,1)
    $btnClose=New-Object Windows.Forms.Button;$btnClose.Text='Close';$btnClose.Width=85;$btnKiosk=New-Object Windows.Forms.Button;$btnKiosk.Text='Launch Kiosk';$btnKiosk.Width=105;$btnNormal=New-Object Windows.Forms.Button;$btnNormal.Text='Launch Normal';$btnNormal.Width=105;$btnRefresh=New-Object Windows.Forms.Button;$btnRefresh.Text='Save && Refresh HTML';$btnRefresh.Width=135;$btnReset=New-Object Windows.Forms.Button;$btnReset.Text='Reset Defaults';$btnReset.Width=105;$actions.Controls.AddRange(@($btnClose,$btnKiosk,$btnNormal,$btnRefresh,$btnReset));foreach($b in @($btnClose,$btnKiosk,$btnNormal,$btnRefresh,$btnReset)){$b.Height=30;$b.Margin=New-Object Windows.Forms.Padding(4,3,4,3)}

    function Set-Status([string]$text){Add-Log $text}
    function Clear-PreviewImage{if($preview.Image){$old=$preview.Image;$preview.Image=$null;$old.Dispose()}}
    function Convert-PreviewFormat {
        param([DateTime]$Value,[string]$Format)
        if([string]::IsNullOrWhiteSpace($Format)){return ''}
        return [regex]::Replace(
            $Format,
            'YYYY|YY|MMMM|MMM|MM|M|DD|D|dddd|ddd|HH|hh|mm|ss|A',
            [Text.RegularExpressions.MatchEvaluator]{
                param($match)
                switch -CaseSensitive ($match.Value) {
                    'YYYY' { $Value.ToString('yyyy') }
                    'YY'   { $Value.ToString('yy') }
                    'MMMM' { $Value.ToString('MMMM') }
                    'MMM'  { $Value.ToString('MMM') }
                    'MM'   { $Value.ToString('MM') }
                    'M'    { [string]$Value.Month }
                    'DD'   { $Value.ToString('dd') }
                    'D'    { [string]$Value.Day }
                    'dddd' { $Value.ToString('dddd') }
                    'ddd'  { $Value.ToString('ddd') }
                    'HH'   { $Value.ToString('HH') }
                    'hh'   { $Value.ToString('hh') }
                    'mm'   { $Value.ToString('mm') }
                    'ss'   { $Value.ToString('ss') }
                    'A'    { $Value.ToString('tt') }
                }
            }
        )
    }
    function Get-PreviewPixels{param([string]$Value,[double]$Fallback);if($Value -match '^\s*([0-9]+(?:\.[0-9]+)?)vw\s*$'){return ([Math]::Max(8.0,$preview.ClientSize.Width*([double]$matches[1]/100.0)))};return ([Math]::Max(8.0,$preview.ClientSize.Width*($Fallback/100.0)))}
    function Render-Preview {
        $canvasWidth=1200
        $screenBounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds
        $screenAspect=if($screenBounds.Height -gt 0){$screenBounds.Width/[double]$screenBounds.Height}else{16.0/9.0}
        $canvasHeight=[int][Math]::Round($canvasWidth/$screenAspect)
        $bitmap=New-Object Drawing.Bitmap($canvasWidth,$canvasHeight)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $backgroundImage=$null;$timeFont=$null;$dateFont=$null
        $textBrush=$null;$shadowBrush=$null;$overlayBrush=$null;$format=$null
        try{
            $graphics.Clear([Drawing.ColorTranslator]::FromHtml([string]$script:Config.BackgroundColor))
            $path=Resolve-BackgroundPath $script:Config
            if($path){
                try{
                    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                    try{$temp=[Drawing.Image]::FromStream($stream);$backgroundImage=New-Object Drawing.Bitmap($temp);$temp.Dispose()}finally{$stream.Dispose()}
                    $scale=[Math]::Max($canvasWidth/[double]$backgroundImage.Width,$canvasHeight/[double]$backgroundImage.Height)
                    $drawWidth=[int][Math]::Ceiling($backgroundImage.Width*$scale)
                    $drawHeight=[int][Math]::Ceiling($backgroundImage.Height*$scale)
                    $drawX=[int](($canvasWidth-$drawWidth)/2)
                    $drawY=[int](($canvasHeight-$drawHeight)/2)
                    $graphics.DrawImage($backgroundImage,$drawX,$drawY,$drawWidth,$drawHeight)
                    $lblBackground.Text=$path
                }catch{$lblBackground.Text='Image could not be previewed.'}
            }else{$lblBackground.Text="Solid color: $($script:Config.BackgroundColor)"}

            $opacity=[Math]::Max(0,[Math]::Min(0.85,[double]$nudOpacity.Value))
            $overlayBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb([int](255*$opacity),0,0,0))
            $graphics.FillRectangle($overlayBrush,0,0,$canvasWidth,$canvasHeight)

            $now=Get-Date
            $timeText=Convert-PreviewFormat $now ([string]$cmbTimeFormat.Text)
            $dateText=Convert-PreviewFormat $now ([string]$cmbDateFormat.Text)
            $timeFamily=[string]$script:Config.TimeFontFamily;if([string]::IsNullOrWhiteSpace($timeFamily)){$timeFamily='Segoe UI'}
            $dateFamily=[string]$script:Config.DateFontFamily;if([string]::IsNullOrWhiteSpace($dateFamily)){$dateFamily='Segoe UI'}
            $timePixels=[single]([Math]::Max(16,$canvasWidth*(([double](([string]$script:Config.TimeFontSize) -replace '[^0-9.]',''))/100)))
            $datePixels=[single]([Math]::Max(12,$canvasWidth*(([double](([string]$script:Config.DateFontSize) -replace '[^0-9.]',''))/100)))
            try{$color=[Drawing.ColorTranslator]::FromHtml($txtFontColor.Text)}catch{$color=[Drawing.Color]::White}
            try{
                $timeStyle=try{[Drawing.FontStyle]::$([string]$script:Config.TimeFontStyle)}catch{[Drawing.FontStyle]::Regular};$dateStyle=try{[Drawing.FontStyle]::$([string]$script:Config.DateFontStyle)}catch{[Drawing.FontStyle]::Regular}
                $timeFont=New-Object Drawing.Font($timeFamily,$timePixels,$timeStyle,[Drawing.GraphicsUnit]::Pixel)
                $dateFont=New-Object Drawing.Font($dateFamily,$datePixels,$dateStyle,[Drawing.GraphicsUnit]::Pixel)
            }catch{
                $timeFont=New-Object Drawing.Font('Segoe UI',$timePixels,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
                $dateFont=New-Object Drawing.Font('Segoe UI',$datePixels,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
            }
            $textBrush=New-Object Drawing.SolidBrush($color)
            $shadowBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(180,0,0,0))
            $format=New-Object Drawing.StringFormat
            $format.FormatFlags=[Drawing.StringFormatFlags]::NoWrap
            $timeMeasured=$graphics.MeasureString($timeText,$timeFont,[int]$canvasWidth,$format)
            $dateMeasured=$graphics.MeasureString($dateText,$dateFont,[int]$canvasWidth,$format)
            $timeX=[single](($canvasWidth-$timeMeasured.Width)/2)
            $timeY=[single](($canvasHeight*0.46)-($timeMeasured.Height/2))
            $dateX=[single](($canvasWidth-$dateMeasured.Width)/2)
            $dateY=[single](($canvasHeight*0.59)-($dateMeasured.Height/2))
            $graphics.DrawString($timeText,$timeFont,$shadowBrush,[Drawing.PointF]::new(($timeX+3),($timeY+3)),$format)
            $graphics.DrawString($dateText,$dateFont,$shadowBrush,[Drawing.PointF]::new(($dateX+2),($dateY+2)),$format)
            $graphics.DrawString($timeText,$timeFont,$textBrush,[Drawing.PointF]::new($timeX,$timeY),$format)
            $graphics.DrawString($dateText,$dateFont,$textBrush,[Drawing.PointF]::new($dateX,$dateY),$format)
        }
        finally{
            if($format){$format.Dispose()};if($overlayBrush){$overlayBrush.Dispose()};if($shadowBrush){$shadowBrush.Dispose()};if($textBrush){$textBrush.Dispose()};if($dateFont){$dateFont.Dispose()};if($timeFont){$timeFont.Dispose()};if($backgroundImage){$backgroundImage.Dispose()};$graphics.Dispose()
        }
        $old=$preview.Image;$preview.Image=$bitmap;if($old){$old.Dispose()}
    }
    function Update-Preview { try{Render-Preview}catch{Set-Status ('Preview disabled: '+$_.Exception.Message)} }
    function Config-To-Controls{
        $timePt=([double](([string]$script:Config.TimeFontSize)-replace '[^0-9.]',''))/0.75;$txtTimeFont.Text=('{0}, {1}, {2:0.#} pt' -f [string]$script:Config.TimeFontFamily,[string]$script:Config.TimeFontStyle,$timePt)
        $datePt=([double](([string]$script:Config.DateFontSize)-replace '[^0-9.]',''))/0.30;$txtDateFont.Text=('{0}, {1}, {2:0.#} pt' -f [string]$script:Config.DateFontFamily,[string]$script:Config.DateFontStyle,$datePt)
        $txtFontColor.Text=[string]$script:Config.FontColor;$nudOpacity.Value=[decimal][double]$script:Config.OverlayOpacity
        $cmbTimeFormat.Text=[string]$script:Config.TimeFormat;$cmbDateFormat.Text=[string]$script:Config.DateFormat;switch([string]$script:Config.TextShadow){'none'{$cmbShadow.SelectedItem='None'};'0 1px 3px rgba(0,0,0,0.45)'{$cmbShadow.SelectedItem='Soft'};'0 2px 6px rgba(0,0,0,0.60)'{$cmbShadow.SelectedItem='Medium'};'0 3px 10px rgba(0,0,0,0.80)'{$cmbShadow.SelectedItem='Strong'};default{$cmbShadow.SelectedItem='Medium'}}
        Update-Preview
    }
    function Controls-To-Config {
        $fontColor=[string]$txtFontColor.Text
        if($fontColor -notmatch '^#[0-9A-Fa-f]{6}$'){throw 'Font color must use #RRGGBB format.'}
        $timeFamily=[string]$script:Config.TimeFontFamily
        if([string]::IsNullOrWhiteSpace($timeFamily)){$timeFamily='Segoe UI'}
        $dateFamily=[string]$script:Config.DateFontFamily
        if([string]::IsNullOrWhiteSpace($dateFamily)){$dateFamily='Segoe UI'}
        $script:Config.FontFamily="'$timeFamily', Arial, sans-serif"
        $script:Config.TimeFontFamily=$timeFamily
        $script:Config.DateFontFamily=$dateFamily
        $script:Config.FontColor=$fontColor.ToUpperInvariant()
        $script:Config.OverlayOpacity=[double]$nudOpacity.Value
        $script:Config.TimeFormat=[string]$cmbTimeFormat.Text
        $script:Config.DateFormat=[string]$cmbDateFormat.Text
        $script:Config.TextShadow=switch([string]$cmbShadow.SelectedItem){'None'{'none'};'Soft'{'0 1px 3px rgba(0,0,0,0.45)'};'Strong'{'0 3px 10px rgba(0,0,0,0.80)'};default{'0 2px 6px rgba(0,0,0,0.60)'}}
        $script:Config=ConvertTo-CanonicalConfig $script:Config
    }
    function Run-Safely([scriptblock]$work){try{&$work}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'LobbyTime',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null;Set-Status 'Operation failed.'}}

    $previewTimer=New-Object Windows.Forms.Timer
    $previewTimer.Interval=1000
    $previewTimer.Add_Tick({
        try{Render-Preview}
        catch{$previewTimer.Stop();Set-Status ('Preview disabled: '+$_.Exception.Message)}
    })
    $previewTimer.Start()

    $btnBrowse.Add_Click({Run-Safely{$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Title='Select LobbyTime background';$dialog.Filter='Image files (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png|All files (*.*)|*.*';$wallpaperFolder='C:\Windows\Web';if(Test-Path -LiteralPath $wallpaperFolder -PathType Container){$dialog.InitialDirectory=$wallpaperFolder}else{$pictures=[Environment]::GetFolderPath('MyPictures');if($pictures){$dialog.InitialDirectory=$pictures}};if($dialog.ShowDialog($form)-eq[Windows.Forms.DialogResult]::OK){$script:Config.BackgroundFileName=Import-BackgroundImage $dialog.FileName;Save-Config $script:Config;Update-Preview;Set-Status 'Background image saved.'}}})
    $btnWallpaper.Add_Click({Run-Safely{$wallpaper=Get-CurrentWindowsWallpaper;if(-not$wallpaper){throw 'The current Windows wallpaper path could not be found. Use Browse Image instead.'};$script:Config.BackgroundFileName=Import-BackgroundImage $wallpaper;Save-Config $script:Config;Update-Preview;Set-Status 'Current Windows wallpaper imported.'}})
    $btnColor.Add_Click({Run-Safely{$color=Show-ColorDialog ([string]$script:Config.BackgroundColor);if($color){$script:Config.BackgroundColor=$color;$script:Config.BackgroundFileName='';Save-Config $script:Config;Update-Preview;Set-Status 'Solid background color saved.'}}})
    $btnClear.Add_Click({$script:Config.BackgroundFileName='';Save-Config $script:Config;Update-Preview;Set-Status 'Background image cleared.'})
    $btnTimeFont.Add_Click({
        $dialog=New-Object Windows.Forms.FontDialog;$dialog.FontMustExist=$true;$dialog.ShowEffects=$true;$dialog.ShowColor=$false
        try{$style=[Drawing.FontStyle]::$([string]$script:Config.TimeFontStyle);$dialogSize=[single]([Math]::Max(6,[Math]::Min(72,([double](([string]$script:Config.TimeFontSize)-replace '[^0-9.]','')/0.75))));$dialog.Font=New-Object Drawing.Font([string]$script:Config.TimeFontFamily,$dialogSize,$style)}catch{$dialog.Font=New-Object Drawing.Font('Segoe UI',12)}
        if($dialog.ShowDialog($form)-eq[Windows.Forms.DialogResult]::OK){$script:Config.TimeFontFamily=$dialog.Font.FontFamily.Name;$script:Config.TimeFontStyle=[string]$dialog.Font.Style;$script:Config.TimeFontSize=('{0:0.##}vw' -f [Math]::Max(2.0,[Math]::Min(18.0,([double]$dialog.Font.SizeInPoints*0.75))));$txtTimeFont.Text=('{0}, {1}, {2:0.#} pt' -f $script:Config.TimeFontFamily,$script:Config.TimeFontStyle,$dialog.Font.SizeInPoints);Render-Preview};$dialog.Dispose()
    })
    $btnDateFont.Add_Click({
        $dialog=New-Object Windows.Forms.FontDialog;$dialog.FontMustExist=$true;$dialog.ShowEffects=$true;$dialog.ShowColor=$false
        try{$style=[Drawing.FontStyle]::$([string]$script:Config.DateFontStyle);$dialogSize=[single]([Math]::Max(6,[Math]::Min(72,([double](([string]$script:Config.DateFontSize)-replace '[^0-9.]','')/0.30))));$dialog.Font=New-Object Drawing.Font([string]$script:Config.DateFontFamily,$dialogSize,$style)}catch{$dialog.Font=New-Object Drawing.Font('Segoe UI',12)}
        if($dialog.ShowDialog($form)-eq[Windows.Forms.DialogResult]::OK){$script:Config.DateFontFamily=$dialog.Font.FontFamily.Name;$script:Config.DateFontStyle=[string]$dialog.Font.Style;$script:Config.DateFontSize=('{0:0.##}vw' -f [Math]::Max(1.5,[Math]::Min(10.0,([double]$dialog.Font.SizeInPoints*0.30))));$txtDateFont.Text=('{0}, {1}, {2:0.#} pt' -f $script:Config.DateFontFamily,$script:Config.DateFontStyle,$dialog.Font.SizeInPoints);Render-Preview};$dialog.Dispose()
    })
    $btnFontColor.Add_Click({$color=Show-ColorDialog $txtFontColor.Text;if($color){$txtFontColor.Text=$color;Render-Preview}})
    foreach($control in @($txtFontColor,$cmbTimeFormat,$cmbDateFormat)){$control.Add_TextChanged({$preview.Invalidate()})};$cmbShadow.Add_SelectedIndexChanged({Controls-To-Config;Render-Preview})
    $btnRefresh.Add_Click({Run-Safely{Controls-To-Config;Save-Config $script:Config;New-LobbyHtml $script:Config|Out-Null;Set-Status 'Saved configuration and refreshed kiosk.html.'}})
    $btnNormal.Add_Click({Run-Safely{Controls-To-Config;Start-LobbyEdge $script:Config;Set-Status 'Launched normal mode.'}})
    $btnKiosk.Add_Click({Run-Safely{Controls-To-Config;Start-LobbyEdge $script:Config -Kiosk;Set-Status 'Launched kiosk mode.'}})
    $btnReset.Add_Click({if([Windows.Forms.MessageBox]::Show('Reset all LobbyTime settings to defaults?','LobbyTime',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)-eq[Windows.Forms.DialogResult]::Yes){$script:Config=ConvertTo-CanonicalConfig $null;Save-Config $script:Config;Config-To-Controls;Set-Status 'Defaults restored.'}})
    $btnClose.Add_Click({$form.Close()});$form.Add_FormClosed({$previewTimer.Stop();$previewTimer.Dispose();Clear-PreviewImage})
    Config-To-Controls;Add-Log 'Ready';[void]$form.ShowDialog()
}

$script:Config=Load-Config
try{switch($Action){'create'{Save-Config $script:Config;New-LobbyHtml $script:Config|Out-Null;Write-Host "HTML written: $script:HtmlPath"};'normal'{Start-LobbyEdge $script:Config};'kiosk'{Start-LobbyEdge $script:Config -Kiosk};default{Show-LobbyTimeGui}}}catch{if($Action -eq 'gui'){[Windows.Forms.MessageBox]::Show($_.Exception.Message,'LobbyTime',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}else{Write-Error $_;exit 1}}
