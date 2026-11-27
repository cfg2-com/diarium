# diarium

Scripts and utilities for exporting and converting [Diarium](https://diariumapp.com/en) journal entries to Markdown format.

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
- [ConvertToMarkdown.ps1](#convertttomarkdownps1)
- [Output Format](#output-format)
- [Troubleshooting](#troubleshooting)

## Requirements

- Windows PC with PowerShell 5.0 or later
- Diarium application installed (for exporting)
- Access to the folder where you export your Diarium backups

## Quick Start

1. Clone this repository
2. Copy and configure your settings:
   ```powershell
   cd src
   cp config.template.psd1 config.psd1
   # Edit config.psd1 with your settings
   ```
3. Run the script:
   ```powershell
   .\ConvertToMarkdown.ps1
   ```

## Configuration

Create a `config.psd1` file in the `/src` folder by copying `config.template.psd1`:

```powershell
@{
    ZipFolder = 'C:\Users\you\Backup\Diarium'
}
```

**Settings:**
- `ZipFolder` (required): The folder where you export your Diarium zip files

## Usage

Run the script from PowerShell in the `/src` directory:

```powershell
.\ConvertToMarkdown.ps1
```

The script will:
1. Scan your `ZipFolder` for Diarium exports
2. Extract contents from zip files
3. Convert entries to Markdown format
4. Organize by date in `Diarium\YYYY\MM` folders
5. Include attachments and location data

## ConvertToMarkdown.ps1

This script automates the conversion of exported Diarium entries into organized Markdown files with the following features:

- **Date-based Organization**: Entries organized by year and month
- **Attachments**: Extracted and linked from entries
- **Location Data**: Preserved from original entries
- **Markdown Format**: Easy to read and version-control friendly

### Export Settings

When exporting from Diarium, ensure you use these settings:

1. **Format**: Save as JSON (not DOCX or other formats)
2. **Attachments**: Check "Create separate files for attachments"

![Export options](export-opts.png "Export options")

## Output Format

The script creates the following directory structure:

```
Diarium\
├── 2024\
│   ├── 01\
│   │   ├── 2024-01-15.md
│   │   ├── 2024-01-20.md
│   │   └── attachments\
│   └── 02\
│       └── 2024-02-10.md
└── ...
```

Each `.md` file contains your journal entry with metadata (location, date, attachments).

## Troubleshooting

**Issue**: Script can't find the zip files
- **Solution**: Verify the `ZipFolder` path in `config.psd1` is correct and contains exported Diarium zip files

**Issue**: Attachments not extracted
- **Solution**: When exporting from Diarium, ensure "Create separate files for attachments" is checked

**Issue**: Permission denied errors
- **Solution**: Ensure you have read/write permissions to the `ZipFolder` and destination directories


