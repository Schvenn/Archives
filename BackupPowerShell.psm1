function backuppowershell ([switch]$force) {# Create an incremental backup of the PowerShell directory tree, with a custom exclusions list.
$startdir = get-location; $rootDir = Split-Path $profile; $rootPath = Resolve-Path $rootDir; $folderName = Split-Path $rootPath -Leaf; $date = Get-Date -Format "MM-dd-yyyy"; $parentDir = Split-Path $rootPath -Parent; $zipFile = Join-Path $parentDir "$folderName - $date.zip"; $backupZipPattern = '^' + [regex]::Escape($folderName) + ' - \d{2}-\d{2}-\d{4}\.zip$'

# Load the user configuration.
$baseModulePath = "$powershell\Modules\BackupPowerShell"; $configPath = Join-Path $baseModulePath "BackupPowerShell.psd1"

if (!(Test-Path $configPath)) {throw "Config file not found at $configPath"}
$config = Import-PowerShellDataFile -Path $configPath

# Check if the newest backup is older than the $maximumage set in the configuration file and set the archive flag, if a new backup is due.
$maximumage = $config.PrivateData.maximumage; $archive = $false; $latestZip = Get-ChildItem -Path $parentDir -File | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if (($latestZip -and $latestZip.LastWriteTime -lt (Get-Date).AddDays(-$maximumage +1)) -or $force) {$archive = $true}

if ($archive) {# Convert simple values to a single case-insensitive Regex pattern.
$rawExclusions = $config.PrivateData.exclusions
if ($rawExclusions -is [string]) {$rawExclusions = @($rawExclusions)}
$escapedPatterns = foreach ($item in $rawExclusions) {[regex]::Escape($item) -replace '\\\*', '.*'}
$exclusions = '(?i)(' + ($escapedPatterns -join '|') + ')'

# Clean up old backups by keeping the last user defined number.
[int]$versionstokeep = $config.PrivateData.versionstokeep - 1; $existingZips = Get-ChildItem -Path $rootDir -Filter "$folderName - *.zip" | Where-Object {$_.Name -match $backupZipPattern} | Sort-Object LastWriteTime -Descending
if ($existingZips.Count -gt $versionstokeep) {$zipsToRemove = $existingZips | Select-Object -Skip $versionstokeep
foreach ($zip in $zipsToRemove) {Write-Host -ForegroundColor red "`nDeleting old backup: $($zip.FullName)"; Remove-Item $zip.FullName -Force}}

# Sanity check
$filesToZip = Get-ChildItem -Path $rootPath -Recurse -File; $fileCount = $filesToZip.Count; $totalSizeBytes = ($filesToZip | Measure-Object -Property Length -Sum).Sum; $totalSizeMB = [math]::Round($totalSizeBytes / 1MB, 2)
if ($fileCount -gt 500 -or $totalSizeMB -gt 100) {Write-Host -ForegroundColor yellow "`nWARNING:"; Write-Host "You're about to zip $fileCount files totaling $totalSizeMB MB."; $response = Read-Host "Proceed? (Y/N)"; if ($response -notin @('Y', 'y')) {Write-Host "Aborted by user."; return}}

# Create the zip
Push-Location $parentDir; try {Compress-Archive -Path $folderName -DestinationPath $zipFile; Write-Host -ForegroundColor green "`nCreated archive: $zipFile"}
catch {Write-Error "An error occurred while creating the zip file: $_"; Pop-Location; return}; Pop-Location

# Remove backup zips and custom user exclusions from within the new zip.
Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Update')
$entriesToRemove = $zip.Entries | Where-Object {$_.Name -match $backupZipPattern -or $_.FullName -match $exclusions}
foreach ($entry in $entriesToRemove) {Write-Host -ForegroundColor DarkGray "Removing zip entry: $($entry.FullName)"; $entry.Delete()}
$zip.Dispose(); ""; sl $startdir

# Move zip file back into original folder
Move-Item -Path $zipFile -Destination $rootPath -Force}}
sal -name bkps -value backuppowershell -scope global

Export-ModuleMember -Function backuppowershell
Export-ModuleMember -Alias bkps

<#
## backuppowershell

Create a ZIP backup of the current user's entire Powershell directory structure, with a customizable exclusion list, history age and history retention settings.
Use -force to create a backup outside of the normal schedule.
##>
