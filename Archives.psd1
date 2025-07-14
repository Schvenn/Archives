@{RootModule = 'Archives.psm1'
ModuleVersion = '1.8'
GUID = '032f83ae-c0cf-426e-b124-46378c639f86'
Author = 'Craig Plath'
CompanyName = 'Plath Consulting Incorporated'
Copyright = '© Craig Plath. All rights reserved.'
Description = 'PowerShell module to backup and restore entire directory structures, with configurable settings.'
PowerShellVersion = '5.1'
FunctionsToExport = @('Archives')
CmdletsToExport = @()
VariablesToExport = @()
AliasesToExport = @()
FileList = @('Archives.psm1')

PrivateData = @{PSData = @{Tags = @('archive', 'zip', 'backup', 'restore', 'powershell')
LicenseUri = ''
ProjectUri = 'https://github.com/Schvenn/Archives'
ReleaseNotes = ''}

maximumage = '14'
exclusions = 'FolderCache.json', 'Transcripts'
versionstokeep = '4'}}
