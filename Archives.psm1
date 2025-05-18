function archives ($mode, $details, [switch]$force) {#Backup or restore files for the current directory.
$startDir = get-location

# Load the user configuration.
$baseModulePath = "$powershell\Modules\Archives"; $configPath = Join-Path $baseModulePath "Archives.psd1"
if (!(Test-Path $configPath)) {throw "Config file not found at $configPath"}
$config = Import-PowerShellDataFile -Path $configPath
$maximumage = $config.PrivateData.maximumage; $rawExclusions = $config.PrivateData.exclusions; [int]$versionstokeep = $config.PrivateData.versionstokeep - 1

if ($mode -match "(?i)^backup" -and $details -match "^(?i)Powershell$") {# Temporarily switch to PowerShell if $details was set to PowerShell.
sl (Split-Path $profile); $startDir = Get-Location}

if ($mode -match "(?i)^backup") {# Create an incremental backup of the current directory recursively, with confirmation if the archive will be >500 files/100mb.
$rootDir = Get-Location; $rootPath = $rootDir.Path; $folderName = Split-Path $rootPath -Leaf; $date = Get-Date -Format "MM-dd-yyyy"; $parentDir = Split-Path $rootPath -Parent; $zipFile = Join-Path $parentDir "$folderName - $date.zip"; $backupZipPattern = '^' + [regex]::Escape($folderName) + ' - \d{2}-\d{2}-\d{4}\.zip$'; 

# Check if the newest backup is older than the $maximumage set in the configuration file and set the archive flag, if a new backup is due.
$maximumage = $config.PrivateData.maximumage; $archive = $false; $latestZip = Get-ChildItem -Path $startDir -File | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (($latestZip -and ($latestZip.Name -match '\d{2}-\d{2}-\d{4}' -and [datetime]::ParseExact($matches[0], 'MM-dd-yyyy', $null) -lt (Get-Date).AddDays(-$maximumage))) -or $force) {$archive = $true}

# Convert simple values to a single case-insensitive Regex pattern.
if ($rawExclusions -is [string]) {$rawExclusions = @($rawExclusions)}
$escapedPatterns = foreach ($item in $rawExclusions) {[regex]::Escape($item) -replace '\\\*', '.*'}
$exclusions = '(?i)(' + ($escapedPatterns -join '|') + ')'

# Clean up old backups, keeping only as many as set in the configuration file.
$existingZips = Get-ChildItem -Path $parentDir -Filter "$folderName\$folderName - *.zip" | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending
if ($existingZips.Count -gt $versionstokeep) {$zipsToRemove = $existingZips | Select-Object -Skip 2
foreach ($zip in $zipsToRemove) {Write-Host -f red "`nDeleting old backup: $($zip.FullName)"; Remove-Item $zip.FullName -Force}}

# Sanity check
$filesToZip = Get-ChildItem -Path $rootPath -Recurse -File; $fileCount = $filesToZip.Count; $totalSizeBytes = ($filesToZip | Measure-Object -Property Length -Sum).Sum; $totalSizeMB = [math]::Round($totalSizeBytes / 1MB, 2)
if ($fileCount -gt 500 -or $totalSizeMB -gt 100) {Write-Host -f yellow "`nWARNING:"; Write-Host "You're about to zip $fileCount files totaling $totalSizeMB MB."; $response = Read-Host "Proceed? (Y/N)"; if ($response -notin @('Y', 'y')) {Write-Host "Aborted by user."; return}}

if ($archive -eq $true) {# Create the zip
Push-Location $parentDir; try {Compress-Archive -Path $folderName -DestinationPath $zipFile; Write-Host -f green "`nCreated archive: $zipFile"} 
catch {Write-Error "An error occurred while creating the zip file: $_"; Pop-Location; return}; Pop-Location

# Remove backup zips and custom user exclusions from within the new zip.
Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Update')
$entriesToRemove = $zip.Entries | Where-Object {$_.Name -match $backupZipPattern -or $_.FullName -match $exclusions}
foreach ($entry in $entriesToRemove) {Write-Host -f darkgray "Removing zip entry: $($entry.FullName)"; $entry.Delete()}
$zip.Dispose(); ""

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