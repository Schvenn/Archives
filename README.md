# Archives
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
