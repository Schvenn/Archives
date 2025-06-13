function archives ($mode, $details, [switch]$force, [switch]$help) {#Backup or restore files for the current directory.
$startDir = get-location

# Load the user configuration.
$baseModulePath = "$powershell\Modules\Archives"; $configPath = Join-Path $baseModulePath "Archives.psd1"
if (!(Test-Path $configPath)) {throw "Config file not found at $configPath"}
$config = Import-PowerShellDataFile -Path $configPath
$maximumage = $config.PrivateData.maximumage; $rawExclusions = $config.PrivateData.exclusions; [int]$versionstokeep = $config.PrivateData.versionstokeep - 1

if (-not $mode -and -not $details -and -not $force -and -not $help) {Write-Host -f cyan "`nUsage: archives (backup/restore) (file pattern/PowerShell) -force -help`n"; return}

if ($help) {# Inline help.
function wordwrap ($field, [int]$maximumlinelength = 65) {# Modify fields sent to it with proper word wrapping.
if ($null -eq $field -or $field.Length -eq 0) {return $null}
$breakchars = ',.;?!\/ '; $wrapped = @()

foreach ($line in $field -split "`n") {if ($line.Trim().Length -eq 0) {$wrapped += ''; continue}
$remaining = $line.Trim()
while ($remaining.Length -gt $maximumlinelength) {$segment = $remaining.Substring(0, $maximumlinelength); $breakIndex = -1

foreach ($char in $breakchars.ToCharArray()) {$index = $segment.LastIndexOf($char)
if ($index -gt $breakIndex) {$breakChar = $char; $breakIndex = $index}}
if ($breakIndex -lt 0) {$breakIndex = $maximumlinelength - 1; $breakChar = ''}
$chunk = $segment.Substring(0, $breakIndex + 1).TrimEnd(); $wrapped += $chunk; $remaining = $remaining.Substring($breakIndex + 1).TrimStart()}

if ($remaining.Length -gt 0) {$wrapped += $remaining}}
return ($wrapped -join "`n")}

function scripthelp ($section) {# (Internal) Generate the help sections from the comments section of the script.
""; Write-Host -f yellow ("-" * 100); $pattern = "(?ims)^## ($section.*?)(##|\z)"; $match = [regex]::Match($scripthelp, $pattern); $lines = $match.Groups[1].Value.TrimEnd() -split "`r?`n", 2; Write-Host $lines[0] -f yellow; Write-Host -f yellow ("-" * 100)
if ($lines.Count -gt 1) {wordwrap $lines[1] 100| Out-String | Out-Host -Paging}; Write-Host -f yellow ("-" * 100)}
$scripthelp = Get-Content -Raw -Path $PSCommandPath; $sections = [regex]::Matches($scripthelp, "(?im)^## (.+?)(?=\r?\n)")
if ($sections.Count -eq 1) {cls; Write-Host "$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) Help:" -f cyan; scripthelp $sections[0].Groups[1].Value; ""; return}

$selection = $null
do {cls; Write-Host "$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) Help Sections:`n" -f cyan; for ($i = 0; $i -lt $sections.Count; $i++) {
"{0}: {1}" -f ($i + 1), $sections[$i].Groups[1].Value}
if ($selection) {scripthelp $sections[$selection - 1].Groups[1].Value}
$input = Read-Host "`nEnter a section number to view"
if ($input -match '^\d+$') {$index = [int]$input
if ($index -ge 1 -and $index -le $sections.Count) {$selection = $index}
else {$selection = $null}} else {""; return}}
while ($true); return}

# Function to create the ZIP files.
function Add-To-Zip ($sourceDir, $zipPath) {Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipPath) {Remove-Item $zipPath -Force}
$tempDir = Join-Path $env:TEMP "archive_tmp_$(Get-Random)"; Copy-Item $sourceDir $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$tempDir\Transcripts" -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {try {$stream = [System.IO.File]::Open($_.FullName, 'Open', 'Read', 'ReadWrite'); $stream.Close()} catch {Write-Warning "Skipping locked file: $($_.Name)"; Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue}}
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath)
Write-Host -f green "`nCreated archive: $zipPath"; Remove-Item $tempDir -Recurse -Force}

if ($mode -match "(?i)^backup" -and $details -match "^(?i)Powershell$") {# Temporarily switch to PowerShell if $details was set to PowerShell.
sl (Split-Path $profile); $startDir = Get-Location}

if ($mode -match "(?i)^backup") {# Create an incremental backup of the current directory recursively, with confirmation if the archive will be >500 files/100mb.
$rootDir = Get-Location; $rootPath = $rootDir.Path; $folderName = Split-Path $rootPath -Leaf; $date = Get-Date -Format "MM-dd-yyyy"; $parentDir = Split-Path $rootPath -Parent; $zipFile = Join-Path $parentDir "$folderName - $date.zip"; $backupZipPattern = '^' + [regex]::Escape($folderName) + ' - \d{2}-\d{2}-\d{4}\.zip$'; 

# Check if the newest backup is older than the $maximumage set in the configuration file and set the archive flag, if a new backup is due.
$maximumage = $config.PrivateData.maximumage; $archive = $false; $latestZip = Get-ChildItem -Path $startDir -File | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (($latestZip -and ($latestZip.Name -match '\d{2}-\d{2}-\d{4}' -and [datetime]::ParseExact($matches[0], 'MM-dd-yyyy', $null) -lt (Get-Date).AddDays(-$maximumage))) -or $force -or -not $latestZip) {$archive = $true}

# Convert simple values to a single case-insensitive Regex pattern.
if ($rawExclusions -is [string]) {$rawExclusions = @($rawExclusions)}
$escapedPatterns = foreach ($item in $rawExclusions) {[regex]::Escape($item) -replace '\\\*', '.*'}
$exclusions = '(?i)(' + ($escapedPatterns -join '|') + ')'

# Clean up old backups, keeping only as many as set in the configuration file.
$existingZips = Get-ChildItem -Path $parentDir -Filter "$folderName\$folderName - *.zip" | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending
if ($existingZips.Count -gt $versionstokeep) {""; $zipsToRemove = $existingZips | Select-Object -Skip 2
foreach ($zip in $zipsToRemove) {Write-Host -f red "Deleting old backup: $($zip.FullName)"; Remove-Item $zip.FullName -Force}}

# Sanity check
$filesToZip = Get-ChildItem -Path $rootPath -Recurse -File; $fileCount = $filesToZip.Count; $totalSizeBytes = ($filesToZip | Measure-Object -Property Length -Sum).Sum; $totalSizeMB = [math]::Round($totalSizeBytes / 1MB, 2)
if ($fileCount -gt 500 -or $totalSizeMB -gt 100) {Write-Host -f yellow "`nWARNING:"; Write-Host "You're about to zip $fileCount files totaling $totalSizeMB MB."; $response = Read-Host "Proceed? (Y/N)"; if ($response -notin @('Y', 'y')) {Write-Host "Aborted by user."; return}}

if ($archive -eq $true) {# Create the zip
Push-Location $parentDir; Add-To-Zip $folderName $zipFile; Pop-Location

# Remove backup zips and custom user exclusions from within the new zip.
try {$zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Update')
$entriesToRemove = $zip.Entries | Where-Object {$_.Name -match $backupZipPattern -or $_.FullName -match $exclusions}
foreach ($entry in $entriesToRemove) {Write-Host -f darkgray "Removing zip entry: $($entry.FullName)"; $entry.Delete()}}
catch {Write-Host -f red "Failed to modify zip: $_"}
finally {if ($zip) {$zip.Dispose(); ""}}

# Move zip file back into original folder
Move-Item -Path $zipFile -Destination $rootPath -Force}; sl $startdir}

if ($mode -match "(?i)^restore$") {# Restore one of the backup files to the current directory structure based on the date provided or select a file to restore.
$rootDir = Get-Location; $folderName = Split-Path $rootDir -Leaf; $parentDir = Split-Path $rootDir -Parent

# If no $details is provided, present a menu of viable options for restore.
if (-not $details) {$files = Get-ChildItem -Filter *.zip
Write-Host -f yellow "`nSelect an Archive to Restore:`n"
for ($i = 0; $i -lt $files.Count; $i++) {Write-Host -f cyan "$($i + 1)`: " -n; Write-Host -f white "$($files[$i].Name)"}
Write-Host -f cyan "`nEnter the number of the zip file to select" -n; $selection = Read-Host " "
if ($selection -match '^\d+$' -and $selection -ge 1 -and $selection -le $files.Count) {$selectedFile = $files[$selection - 1]} else {return}
$zipFilePath = $selectedFile}

# If $details was provided, match the file pattern for restoring a ZIP.
if ($details) {$matchingZips = Get-ChildItem -Path $rootDir -Filter '*.zip' | Where-Object {$_.Name -match [regex]::Escape($details)}
if ($matchingZips.Count -eq 0) {Write-Host -f red "`nNo ZIP archive found matching that file pattern.`n"; return}
if ($matchingZips.Count -gt 1) {Write-Host -f cyan "`nThere is more than one ZIP archive matching that file pattern: " -n; ($matchingZips | Select-Object -ExpandProperty Name) -join ", " | Write-Host -f white; ""; return}
$zipFileName = $matchingZips[0].Name; $zipFilePath = Join-Path $parentDir (Join-Path $folderName $zipFileName)}
if (-Not (Test-Path -Path $zipFilePath)) {Write-Host -f red "`nBackup zip not found: $zipFilePath`n"; return}

# Restore.
Write-Host -f white "`nRestoring '$zipFilePath' to: $parentDir"
try {Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $parentDir, $true); Write-Host "Restore complete.`n"} 
catch {Write-Host -f red "Failed to restore from backup: $_`n"}}; ""}

Export-ModuleMember -Function archives

<#
## Archives

This module will provide you with a very basic archival backup and retrieval utility that creates and restores backups based on a recursive directory structure.

Usage: archives (backup/restore) (file pattern/PowerShell) -force -help

Configuration:
•  In the accompanying PSD1 file you can specify 3 different variables:

PrivateData = @{exclusions = @('FolderCache.json', 'Transcripts')
versionstokeep = 4
maximumage = 14}

• Exclusions is a comma separated list of file patterns to exclude.
• Versionstokeep specifies the maximum number of ZIP archives to keep that match the file pattern: "folder - mm-dd-yyy.zip".
• Maximumage represents the number of days a ZIP file is allowed to be before another backup is created. This can be overriden with the -force switch.

Backups:
• Backup will backup the current directory structure, including the current directory, recursively.
• Specify "PowerShell" in order to switch to the user's $profile directory, create a backup of that directory structure and switch back to the current directory.
• Use the -force switch to create a backup, even if the latest ZIP archive is newer than the specified maximumage in the configuration file.

Restoration:
• Restore will unZip files matching the backup file pattern: "folder - mm-dd-yyy.zip".
• As this is a very simple tool, it will only extract files in the ZIP file, overwriting existing copies of files. New files will remain unchanged.
• If no other parameters are provided, the module will present a menu of matching files to use for the extraction.
• If a file pattern is provided, the module will attempt to match the pattern to one of the viable ZIP archives for extraction.
• If there are too many matches or no matches for the specified file pattern, the module will fail gracefully, with an accompanying message.

This tool is intentionally simple, designed to create living archives for basic versioning purposes. It should not be relied on as a sole backup solution. Since the archive resides within the same directory that it is backing up, it's vulnerable to accidental deletion or file system corruption. I built it as a lightweight way to version active directories, like code bases or evolving documents, and for that purpose, it serves a practical and effective role.
##>
