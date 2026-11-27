# Diarium Utilities

This repository contains PowerShell scripts and utilities for working with [Diarium](https://diariumapp.com/en) journaling software.

## Overview

The primary utility here is `ConvertToMarkdown.ps1`, which exports your Diarium journal entries from zip exports and converts them to Markdown format with organized folder structures by date, plus attachments and location data.

## Development Guidelines

- **Scripts**: Use PowerShell so anyone on a Windows PC can run them without additional software
- **Source Code**: All scripts belong in the `/src` folder
- **Configuration**: Settings are externalized and read from `config.psd1`
  - Users should copy `config.template.psd1` to `config.psd1` and customize it
  - `config.psd1` is excluded from version control (don't check in personal settings)

## Getting Started

See [README.md](README.md) for setup and usage instructions.