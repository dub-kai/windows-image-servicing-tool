# Windows Image Servicing Tool

PowerShell WPF tool for mounting, servicing, and updating Windows images.

## Features

- Mount Windows `WIM` and `ESD` images from ISO media or standalone files
- Inspect available image indexes and mounted images
- Read, add, and remove offline drivers from mounted images
- Read installed packages from mounted images
- Search, review, and download updates from the Microsoft Update Catalog
- Integrate downloaded updates into a mounted image

## Project Structure

- `Core/` application bootstrap, config, logging, and app state
- `Services/` DISM, image, driver, ISO, and update logic
- `UI/` WPF XAML pages, controllers, and UI helpers
- `WinImageAdmin.ps1` application entry point

## Start

Run the app from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\WinImageAdmin.ps1
```

The app will relaunch itself with elevated rights when required.

## Notes

- `Logs/`, `Work/`, and `Mount/` are ignored in Git because they contain local runtime artifacts
- The Driver page defaults to the faster non-Inbox view and reloads automatically when filter options change

## Status

Active local development branch:

- `codex/driver-ux-and-ui-polish`
