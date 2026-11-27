<#
.SYNOPSIS
Extracts a zip file in a target folder and marks the archive as converted.

.DESCRIPTION
Looks for the first .zip file in the target folder, extracts it to the same
folder, then renames the archive from [file].zip to [file].zip.converted.
The target folder can be passed with -ZipFolder or set in
config.psd1.

.PARAMETER ZipFolder
Path to the folder that contains the zip file to extract.

.PARAMETER Overwrite
If $true, overwrites existing markdown files and attachments.
If $false (default), skips existing files and logs them as skipped.

.EXAMPLE
.\ConvertToMarkdown.ps1 -ZipFolder 'C:\Exports\Diarium'
.\ConvertToMarkdown.ps1 -ZipFolder 'C:\Exports\Diarium' -Overwrite $true

.NOTES
If -ZipFolder is not provided, the script reads ZipFolder from
config.psd1 in the script folder.

If -Overwrite is not provided, the script reads Overwrite from
config.psd1 in the script folder (default: $false).
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ZipFolder,
    
    [Parameter(Mandatory = $false)]
    [bool]$Overwrite = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logFilePath = $null

function Log-Message {
    param(
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    Write-Host $logEntry
    
    if ($null -ne $logFilePath -and (Test-Path -LiteralPath (Split-Path -Parent $logFilePath))) {
        $logEntry | Out-File -LiteralPath $logFilePath -Append -Encoding UTF8
    }
}

function Normalize-SpecialCharacters {
    param(
        [string]$Text
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    
    # Handle literal Unicode escape sequences in the string
    $Text = $Text -replace '\\u2018', "'"  # \u2018 literal
    $Text = $Text -replace '\\u2019', "'"  # \u2019 literal
    $Text = $Text -replace '\\u201C', '"'  # \u201C literal
    $Text = $Text -replace '\\u201D', '"'  # \u201D literal
    $Text = $Text -replace '\\u201E', '"'  # \u201E literal
    $Text = $Text -replace '\\u201F', '"'  # \u201F literal
    $Text = $Text -replace '\\u2013', '-'  # \u2013 literal
    $Text = $Text -replace '\\u2014', '-'  # \u2014 literal
    $Text = $Text -replace '\\u2026', '...'  # \u2026 literal
    $Text = $Text -replace '\\u00A0', ' '  # \u00A0 literal
    
    # Handle actual Unicode characters
    $Text = $Text -replace '\u2018', "'"  # left single quotation mark
    $Text = $Text -replace '\u2019', "'"  # right single quotation mark
    $Text = $Text -replace '`', "'"       # backtick
    
    $Text = $Text -replace '\u201C', '"'  # left double quotation mark
    $Text = $Text -replace '\u201D', '"'  # right double quotation mark
    $Text = $Text -replace '\u201E', '"'  # double low-9 quotation mark (German)
    $Text = $Text -replace '\u201F', '"'  # double high-reversed-9 quotation mark
    
    $Text = $Text -replace '\u2013', '-'  # en-dash
    $Text = $Text -replace '\u2014', '-'  # em-dash
    
    $Text = $Text -replace '\u2026', '...'  # ellipsis
    
    $Text = $Text -replace '\u00A0', ' '  # non-breaking space
    
    return $Text
}



$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'config.psd1'

if ([string]::IsNullOrWhiteSpace($ZipFolder) -and (Test-Path -LiteralPath $configPath)) {
    try {
        $config = Import-PowerShellDataFile -LiteralPath $configPath
    }
    catch {
        # Fallback for environments where Import-PowerShellDataFile is unavailable
        # Safely dot-source the .psd1 file as a hashtable
        $config = & ([scriptblock]::Create((Get-Content -LiteralPath $configPath -Raw)))
    }
    
    if ($null -ne $config -and $config.ContainsKey('ZipFolder')) {
        $ZipFolder = [string]$config.ZipFolder
    }
    
    if ($null -ne $config -and $config.ContainsKey('Overwrite')) {
        $Overwrite = [bool]$config.Overwrite
    }
}

if ([string]::IsNullOrWhiteSpace($ZipFolder)) {
    throw "No zip folder was provided. Pass -ZipFolder or set ZipFolder in $configPath."
}

if (-not (Test-Path -LiteralPath $ZipFolder -PathType Container)) {
    throw "The folder '$ZipFolder' does not exist."
}

# Create Diarium folder early
$diariumFolder = Join-Path -Path $ZipFolder -ChildPath 'Diarium'
if (-not (Test-Path -LiteralPath $diariumFolder)) {
    New-Item -Path $diariumFolder -ItemType Directory | Out-Null
}

$zipFile = Get-ChildItem -LiteralPath $ZipFolder -Filter '*.zip' -File | Select-Object -First 1
$convertedZipFile = Get-ChildItem -LiteralPath $ZipFolder -Filter '*.zip.converted' -File | Select-Object -First 1

if ($null -eq $zipFile -and $null -eq $convertedZipFile) {
    $msg = "No .zip or .zip.converted file found in '$ZipFolder'."
    Write-Host $msg
    return
}

# Initialize log file path based on zip file base name
$zipFileBaseName = if ($null -ne $zipFile) { 
    [System.IO.Path]::GetFileNameWithoutExtension($zipFile.Name) 
} else { 
    [System.IO.Path]::GetFileNameWithoutExtension(($convertedZipFile.Name -replace '\.converted$', ''))
}
$logFilePath = Join-Path -Path $diariumFolder -ChildPath "ConvertToMarkdown-$zipFileBaseName.log"

if ($null -eq $convertedZipFile) {
    # Extraction not yet done, proceed with extraction
    Log-Message "Starting extraction of '$($zipFile.Name)'..."
    try {
        Expand-Archive -Path $zipFile.FullName -DestinationPath $ZipFolder -ErrorAction Stop
        Log-Message "Successfully extracted '$($zipFile.Name)' using Expand-Archive"
    }
    catch {
        # Fallback: Use .NET System.IO.Compression if Expand-Archive fails
        Log-Message "Expand-Archive failed, using .NET fallback: $_"
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
        try {
            $entryCount = $zipArchive.Entries.Count
            Log-Message "Extracting $entryCount files from zip using .NET..."
            $extractedCount = 0
            foreach ($entry in $zipArchive.Entries) {
                $extractPath = Join-Path -Path $ZipFolder -ChildPath $entry.FullName
                $directory = Split-Path -Path $extractPath -Parent
                if (-not (Test-Path -LiteralPath $directory)) {
                    New-Item -Path $directory -ItemType Directory -Force | Out-Null
                }
                if ($entry.FullName -notmatch '/$') {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $extractPath, $true)
                    $extractedCount++
                    if ($extractedCount % 100 -eq 0) {
                        Log-Message "Extracted $extractedCount/$entryCount files..."
                    }
                }
            }
            Log-Message "Successfully extracted all $extractedCount files using .NET"
        }
        finally {
            $zipArchive.Dispose()
        }
    }

    # Rename the media folder to [filebase]-media
    $mediaFolder = Join-Path -Path $ZipFolder -ChildPath 'media'
    $renamedMediaFolder = Join-Path -Path $ZipFolder -ChildPath "$zipFileBaseName-media"
    
    if ((Test-Path -LiteralPath $mediaFolder) -and $mediaFolder -ne $renamedMediaFolder) {
        if (Test-Path -LiteralPath $renamedMediaFolder) {
            Log-Message "WARNING: Renamed media folder '$renamedMediaFolder' already exists. Skipping rename."
        }
        else {
            Rename-Item -LiteralPath $mediaFolder -NewName "$zipFileBaseName-media"
            Log-Message "Renamed 'media' folder to '$zipFileBaseName-media'"
        }
    }

    $convertedName = "$($zipFile.Name).converted"
    $convertedPath = Join-Path -Path $ZipFolder -ChildPath $convertedName

    if (Test-Path -LiteralPath $convertedPath) {
        throw "Cannot rename '$($zipFile.FullName)' because '$convertedPath' already exists."
    }

    Rename-Item -LiteralPath $zipFile.FullName -NewName $convertedName
    Log-Message "Renamed '$($zipFile.Name)' to '$convertedName'"
}
else {
    Log-Message "Zip file already converted (found '$($convertedZipFile.Name)'). Skipping extraction."
}

# Find and read the JSON file
Log-Message "Searching for JSON file in '$ZipFolder'..."
$jsonFile = Get-ChildItem -LiteralPath $ZipFolder -Filter '*.json' -File -Recurse | Select-Object -First 1

if ($null -eq $jsonFile) {
    Log-Message "ERROR: No .json file found in '$ZipFolder'."
    return
}

Log-Message "Found JSON file: $($jsonFile.Name)"
Log-Message "Parsing JSON file..."

try {
    $json = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    # Ensure entries is an array
    if ($json -is [array]) {
        [array]$entries = $json
    }
    else {
        [array]$entries = @($json)
    }
    Log-Message "Successfully parsed JSON with $($entries.Count) entries"
}
catch {
    Log-Message "ERROR: Failed to parse JSON file: $_"
    throw "Failed to parse JSON file: $_"
}

# Determine the actual media folder name (renamed to [zipfilebase]-media)
$mediaFolderName = "$zipFileBaseName-media"
Log-Message "Using media folder: $mediaFolderName"

Log-Message "================================"
Log-Message "Conversion started"
Log-Message "ZipFolder: $ZipFolder"
Log-Message "Overwrite: $Overwrite"
Log-Message "Output folder: $diariumFolder"
Log-Message "Log file: $logFilePath"
Log-Message "Media folder: $mediaFolderName"
Log-Message "================================"
Log-Message "Processing $($entries.Count) entries..."

# Initialize counters for statistics
$entriesWritten = 0
$entriesSkipped = 0
$attachmentsWritten = 0
$attachmentsSkipped = 0

# Track entries per day to handle duplicates with the same timestamp
$entriesPerDay = @{}

# Process each entry
foreach ($entry in $entries) {
    $dateString = $entry.date
    $heading = if ($entry | Get-Member -Name heading -ErrorAction SilentlyContinue) { $entry.heading } else { $null }
    $html = if ($entry | Get-Member -Name html -ErrorAction SilentlyContinue) { $entry.html } else { $null }
    $attachments = if ($entry | Get-Member -Name attachments -ErrorAction SilentlyContinue) { $entry.attachments } else { $null }
    $location = if ($entry | Get-Member -Name location -ErrorAction SilentlyContinue) { $entry.location } else { $null }
    
    # Normalize special characters in heading
    $heading = Normalize-SpecialCharacters -Text $heading
    
    # Skip entries without required fields
    if ([string]::IsNullOrWhiteSpace($dateString)) {
        Write-Warning "Skipping entry without date"
        return
    }
    
    # Parse the date
    $date = [datetime]::Parse($dateString)
    $year = $date.Year
    $month = $date.Month.ToString('d2')
    $day = $date.Day.ToString('d2')
    $hour24 = $date.ToString('HH')
    $minute = $date.ToString('mm')
    $second = $date.ToString('ss')
    $timeFormatted = "$hour24$minute$second"
    
    # Create year/month folder structure
    $yearFolder = Join-Path -Path $diariumFolder -ChildPath $year
    $monthFolder = Join-Path -Path $yearFolder -ChildPath $month
    $attachmentsFolder = Join-Path -Path $monthFolder -ChildPath 'attachments'
    
    if (-not (Test-Path -LiteralPath $yearFolder)) {
        New-Item -Path $yearFolder -ItemType Directory | Out-Null
    }
    
    if (-not (Test-Path -LiteralPath $monthFolder)) {
        New-Item -Path $monthFolder -ItemType Directory | Out-Null
    }
    
    if (-not (Test-Path -LiteralPath $attachmentsFolder)) {
        New-Item -Path $attachmentsFolder -ItemType Directory | Out-Null
    }
    
    # Create filename: YYYY-mm-dd-HHmmss.md with per-day counter for duplicates
    $dayKey = "$year-$month-$day"
    if (-not $entriesPerDay.ContainsKey($dayKey)) {
        $entriesPerDay[$dayKey] = 0
    }
    $entriesPerDay[$dayKey]++
    $entryNumber = $entriesPerDay[$dayKey]
    
    if ($entryNumber -eq 1) {
        $fileName = "$year-$month-$day-$timeFormatted.md"
    }
    else {
        $fileName = "$year-$month-$day-$timeFormatted`_$entryNumber.md"
    }
    $filePath = Join-Path -Path $monthFolder -ChildPath $fileName
    
    # Build attachments section and copy files (do this first so we track attachments even if entry is skipped)
    $attachmentsSection = ""
    $datePrefix = "$year-$month-$day"
    [array]$attachmentsArray = @($attachments)
    if ($attachmentsArray.Length -gt 0) {
        $attachmentsSection = "`n`n## Attachments`n"
        foreach ($attachment in $attachmentsArray) {
            $attFileName = Split-Path -Path $attachment -Leaf
            $fileExtension = [System.IO.Path]::GetExtension($attFileName).ToLower()
            $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($attFileName)
            
            # Include entry number if this isn't the first entry of the day to avoid conflicts
            if ($entryNumber -eq 1) {
                $prefixedFileName = "$datePrefix`_$baseFileName$fileExtension"
            }
            else {
                $prefixedFileName = "$datePrefix`_$entryNumber`_$baseFileName$fileExtension"
            }
            
            # Copy the attachment file from media folder to attachments subfolder with date prefix
            # Replace 'media/' prefix with the actual media folder name if it exists
            $attachmentPath = $attachment
            if ($attachmentPath.StartsWith("media/")) {
                $attachmentPath = $attachmentPath -replace "^media/", "$mediaFolderName/"
            }
            $sourceFile = Join-Path -Path $ZipFolder -ChildPath $attachmentPath
            $destFile = Join-Path -Path $attachmentsFolder -ChildPath $prefixedFileName
            
            # Check if destination exists and Overwrite is false
            $shouldCopy = $true
            if ((Test-Path -LiteralPath $destFile) -and -not $Overwrite) {
                Log-Message "Skipped: $destFile"
                $attachmentsSkipped++
                $shouldCopy = $false
            }
            else {
                # Destination doesn't exist (or Overwrite is true), so this will be written/copied
                $attachmentsWritten++
            }
            
            if (Test-Path -LiteralPath $sourceFile) {
                if ($shouldCopy) {
                    Copy-Item -LiteralPath $sourceFile -Destination $destFile -Force | Out-Null
                }
                
                # Handle different media types
                if ($fileExtension -eq '.mp4') {
                    # MP4 videos - embed with HTML5 video tag
                    $attachmentsSection += "`n<video width=`"100%`" controls>`n"
                    $attachmentsSection += "  <source src=`"./attachments/$prefixedFileName`" type=`"video/mp4`">`n"
                    $attachmentsSection += "  Your browser does not support the video tag.`n"
                    $attachmentsSection += "</video>`n"
                }
                elseif ($fileExtension -eq '.webm') {
                    # WebM videos - embed with HTML5 video tag
                    $attachmentsSection += "`n<video width=`"100%`" controls>`n"
                    $attachmentsSection += "  <source src=`"./attachments/$prefixedFileName`" type=`"video/webm`">`n"
                    $attachmentsSection += "  Your browser does not support the video tag.`n"
                    $attachmentsSection += "</video>`n"
                }
                elseif ($fileExtension -in @('.avi', '.mov', '.mkv', '.flv')) {
                    # Other video formats - create link since they may not be natively supported
                    $attachmentsSection += "`n[🎬 $attFileName](./attachments/$prefixedFileName)`n"
                }
                else {
                    # Image files and others - embed as image
                    $attachmentsSection += "`n![$attFileName](./attachments/$prefixedFileName)`n"
                }
            }
            else {
                Write-Warning "Attachment not found: $sourceFile"
                # Still add reference even if file not found
                if ($fileExtension -eq '.mp4') {
                    $attachmentsSection += "`n<video width=`"100%`" controls>`n"
                    $attachmentsSection += "  <source src=`"./attachments/$prefixedFileName`" type=`"video/mp4`">`n"
                    $attachmentsSection += "  Your browser does not support the video tag.`n"
                    $attachmentsSection += "</video>`n"
                }
                elseif ($fileExtension -eq '.webm') {
                    $attachmentsSection += "`n<video width=`"100%`" controls>`n"
                    $attachmentsSection += "  <source src=`"./attachments/$prefixedFileName`" type=`"video/webm`">`n"
                    $attachmentsSection += "  Your browser does not support the video tag.`n"
                    $attachmentsSection += "</video>`n"
                }
                elseif ($fileExtension -in @('.avi', '.mov', '.mkv', '.flv')) {
                    $attachmentsSection += "`n[🎬 $attFileName](./attachments/$prefixedFileName)`n"
                }
                else {
                    $attachmentsSection += "`n![$attFileName](./attachments/$prefixedFileName)`n"
                }
            }
        }
    }
    
    # Check if file exists and Overwrite is false
    if ((Test-Path -LiteralPath $filePath) -and -not $Overwrite) {
        Log-Message "Skipped: $filePath"
        $entriesSkipped++
        continue
    }
    
    # Build frontmatter
    [array]$locationArray = @($location)
    $latitude = if ($locationArray.Length -gt 0) { $locationArray[0] } else { $null }
    $longitude = if ($locationArray.Length -gt 1) { $locationArray[1] } else { $null }
    
    # Build header first to determine the title to use in frontmatter
    $titleForFrontmatter = ""
    if ([string]::IsNullOrWhiteSpace($heading)) {
        $dayOfWeek = $date.ToString('ddd')
        $header = "# $year-$month-$day - $dayOfWeek"
        $titleForFrontmatter = "$year-$month-$day - $dayOfWeek"
    }
    else {
        $header = "# $heading"
        $titleForFrontmatter = $heading
    }
    
    $frontmatter = @"
---
title: $titleForFrontmatter
date: $dateString
latitude: $(if ($null -ne $latitude) { $latitude } else { "" })
longitude: $(if ($null -ne $longitude) { $longitude } else { "" })
---
"@
    
    # Convert HTML to plain text (simple approach: remove tags, decode entities)
    $content = $html -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
    
    # Normalize special characters
    $content = Normalize-SpecialCharacters -Text $content
    
    $content = $content -replace '\s+', ' '

    
    # Build location section with embedded map if latitude and longitude are present
    $locationSection = ""
    if ($null -ne $latitude -and $null -ne $longitude) {
        $locationSection = "`n`n## Location`n"
        $locationSection += "[View on map](https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude&zoom=15)`n"
        $locationSection += "`n<iframe src=`"https://www.openstreetmap.org/export/embed.html?bbox=$($longitude - 0.01),$($latitude - 0.01),$($longitude + 0.01),$($latitude + 0.01)&layer=mapnik&marker=$latitude,$longitude`" width=`"100%`" height=`"400px`" frameborder=`"0`" style=`"border:0`"></iframe>`n"
    }
    
    # Combine all parts
    $markdownContent = @"
$frontmatter

$header

$content$attachmentsSection$locationSection
"@
    
    # Write to file
    Set-Content -LiteralPath $filePath -Value $markdownContent -Encoding UTF8
    Log-Message "Created: $filePath"
    $entriesWritten++
}

Log-Message "================================"
Log-Message "Markdown conversion completed"
Log-Message "================================"
Log-Message "Entries Written/Skipped: $entriesWritten/$entriesSkipped"
Log-Message "Attachments Written/Skipped: $attachmentsWritten/$attachmentsSkipped"
Log-Message "Files created in: $diariumFolder"
Log-Message "================================"

Write-Host ""
Write-Host "Markdown conversion completed. Files created in '$diariumFolder'"
Write-Host ""
Write-Host "Entries Written/Skipped: $entriesWritten/$entriesSkipped"
Write-Host "Attachments Written/Skipped: $attachmentsWritten/$attachmentsSkipped"

# Generate index files
Log-Message "================================"
Log-Message "Generating index files"
Log-Message "================================"

function Get-H1HeaderFromMarkdown {
    param([string]$FilePath)
    
    try {
        $lines = Get-Content -LiteralPath $FilePath -ErrorAction Stop
        
        # Extract title from YAML frontmatter
        $inFrontmatter = $false
        foreach ($line in $lines) {
            if ($line -eq '---') {
                if ($inFrontmatter) {
                    break
                }
                $inFrontmatter = $true
            }
            elseif ($inFrontmatter -and $line -match '^\s*title:\s*(.+?)\s*$') {
                $title = $matches[1].Trim()
                # Remove surrounding quotes if present (for backward compatibility)
                $title = $title -replace '^"(.*)"$', '$1'
                $title = $title -replace "^'(.*)'$", '$1'
                if ($title) {
                    return $title
                }
            }
        }
        
        return $null
    }
    catch {
        Log-Message "Warning: Error reading file $FilePath : $_"
        return $null
    }
}

function Generate-MonthIndex {
    param(
        [string]$MonthFolder,
        [int]$Year,
        [string]$Month
    )
    
    $indexPath = Join-Path -Path $MonthFolder -ChildPath '_index.md'
    
    if (-not (Test-Path -LiteralPath $MonthFolder)) {
        Log-Message "Month folder does not exist: $MonthFolder, skipping"
        return
    }
    
    $entries = @(Get-ChildItem -Path $MonthFolder -Filter '*.md' -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -ne '_index.md' } | 
        Sort-Object Name)
    
    if ($entries.Count -eq 0) {
        return
    }
    
    $monthName = [datetime]::ParseExact("$Year-$Month", "yyyy-MM", $null).ToString('MMMM')
    
    $content = "# $Year - $monthName`n`n"
    $content += "## Entries`n`n"
    
    foreach ($entry in $entries) {
        $heading = Get-H1HeaderFromMarkdown -FilePath $entry.FullName
        if ($null -eq $heading) {
            $heading = $entry.Name -replace '\.md$', ''
        }
        
        $relativePath = $entry.Name
        $content += "- [$heading](./$relativePath)`n"
    }
    
    # Always overwrite index files (regardless of Overwrite parameter)
    Set-Content -LiteralPath $indexPath -Value $content -Encoding UTF8 -Force
    Log-Message "Generated: $indexPath"
}

function Generate-YearIndex {
    param(
        [string]$YearFolder,
        [int]$Year
    )
    
    $indexPath = Join-Path -Path $YearFolder -ChildPath '_index.md'
    $monthFolders = @(Get-ChildItem -Path $YearFolder -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{2}$' } | Sort-Object Name)
    
    if ($monthFolders.Count -eq 0) {
        return
    }
    
    $content = "# $Year`n`n"
    $content += "## Months`n`n"
    
    foreach ($monthFolder in $monthFolders) {
        $monthName = [datetime]::ParseExact("$Year-$($monthFolder.Name)", "yyyy-MM", $null).ToString('MMMM')
        $content += "- [$monthName](./$($monthFolder.Name)/_index.md)`n"
    }
    
    # Always overwrite index files (regardless of Overwrite parameter)
    Set-Content -LiteralPath $indexPath -Value $content -Encoding UTF8 -Force
    Log-Message "Generated: $indexPath"
}

function Generate-RootIndex {
    param([string]$RootFolder)
    
    $indexPath = Join-Path -Path $RootFolder -ChildPath '_index.md'
    $yearFolders = @(Get-ChildItem -Path $RootFolder -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}$' } | 
        Sort-Object Name -Descending)
    
    if ($yearFolders.Count -eq 0) {
        return
    }
    
    $content = "# Diarium Entries`n`n"
    $content += "## Years`n`n"
    
    foreach ($yearFolder in $yearFolders) {
        $year = $yearFolder.Name
        $content += "- [$year](./$year/_index.md)`n"
    }
    
    # Always overwrite index files (regardless of Overwrite parameter)
    Set-Content -LiteralPath $indexPath -Value $content -Encoding UTF8 -Force
    Log-Message "Generated: $indexPath"
}

# Generate root index
Log-Message "Generating root index"
Generate-RootIndex -RootFolder $diariumFolder

# Process each year folder and generate indexes
$yearFolders = @(Get-ChildItem -Path $diariumFolder -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^\d{4}$' } | 
    Sort-Object Name)

foreach ($yearFolder in $yearFolders) {
    $year = [int]$yearFolder.Name
    
    # Generate year index
    Generate-YearIndex -YearFolder $yearFolder.FullName -Year $year
    
    # Process each month folder
    $monthFolders = @(Get-ChildItem -Path $yearFolder.FullName -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{2}$' } | 
        Sort-Object Name)
    
    foreach ($monthFolder in $monthFolders) {
        $month = $monthFolder.Name
        # Generate month index
        Generate-MonthIndex -MonthFolder $monthFolder.FullName -Year $year -Month $month
    }
}

Log-Message "Index generation completed"

