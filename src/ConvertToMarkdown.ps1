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

.EXAMPLE
.\ConvertToMarkdown.ps1 -ZipFolder 'C:\Exports\Diarium'

.NOTES
If -ZipFolder is not provided, the script reads ZipFolder from
config.psd1 in the script folder.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ZipFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
}

if ([string]::IsNullOrWhiteSpace($ZipFolder)) {
    throw "No zip folder was provided. Pass -ZipFolder or set ZipFolder in $configPath."
}

if (-not (Test-Path -LiteralPath $ZipFolder -PathType Container)) {
    throw "The folder '$ZipFolder' does not exist."
}

$zipFile = Get-ChildItem -LiteralPath $ZipFolder -Filter '*.zip' -File | Select-Object -First 1

if ($null -eq $zipFile) {
    Write-Host "No .zip file found in '$ZipFolder'."
    return
}

try {
    Expand-Archive -Path $zipFile.FullName -DestinationPath $ZipFolder -ErrorAction Stop
}
catch {
    # Fallback: Use .NET System.IO.Compression if Expand-Archive fails
    Write-Verbose "Expand-Archive failed, using .NET fallback: $_"
    $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
    try {
        foreach ($entry in $zipArchive.Entries) {
            $extractPath = Join-Path -Path $ZipFolder -ChildPath $entry.FullName
            $directory = Split-Path -Path $extractPath -Parent
            if (-not (Test-Path -LiteralPath $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            if ($entry.FullName -notmatch '/$') {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $extractPath, $true)
            }
        }
    }
    finally {
        $zipArchive.Dispose()
    }
}

$convertedName = "$($zipFile.Name).converted"
$convertedPath = Join-Path -Path $ZipFolder -ChildPath $convertedName

if (Test-Path -LiteralPath $convertedPath) {
    throw "Cannot rename '$($zipFile.FullName)' because '$convertedPath' already exists."
}

Rename-Item -LiteralPath $zipFile.FullName -NewName $convertedName
Write-Host "Extracted '$($zipFile.Name)' to '$ZipFolder' and renamed it to '$convertedName'."