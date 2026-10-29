# Detailed Menu Options Guide
**Shared by RebelTortuga | Free to use**

This independent toolkit includes some procedures based on official Blizzard Support guidance and blue posts. It is **not** an official Blizzard product. Read the prompts and use at your own risk.

## How the graphical menu works
The toolkit uses a **graphical sidebar modeled on the Firefox Toolkit v1.0.0**. Choose a section on the left, then click a numbered action on the right. **Diagnostics** is green, **Optional Support** is blue, and **Installation & Folders**, **Backup & Restore**, **Repair & Reset**, and **Other Tools** use the standard button color. The main window stays open.

Existing WoW actions still have interactive prompts: each action launches a **separate visible PowerShell window** for progress, confirmations and detailed findings. Complete the prompts there. The main window's Results area displays launch messages rather than the full diagnostic output.

Use **Detailed Options Guide (H)** to open this document; **Exit Toolkit** closes the main window. The installation path can be refreshed with **Refresh Installation**, beside the path display.

**Before repairs:** completely exit WoW and Battle.net, including the Battle.net tray process, and make backups.

## Installation & Folders (standard button color)
### 1 — Choose WoW installation
Selects the WoW root, game version folder and executable. The toolkit remembers and validates this choice using `%LOCALAPPDATA%\RebelTortuga\WoW-Toolkit\settings.json`. Use this to change installations or correct a path. No WoW account credentials are saved.

### 2 — Open WoW folder
Opens the selected WoW folder in File Explorer. This action is for inspection and does not itself modify game files.

### 3 — Saved Logs
Opens the repair-log directory in File Explorer. The main screen displays **Saved Log Path:** with the full current-session log filename. Logs live under `%LOCALAPPDATA%\RebelTortuga\WoW-Toolkit\Logs`. Diagnostic reports exported through option 6 are saved **separately** wherever you choose. Review logs for local paths before sharing.

## Backup & Restore (standard button color)
### 4 — Save a backup
Copies selected WoW data from the current version folder—`Interface`, `WTF`, `Cache` and `Screenshots` when present—to a destination you choose. Original files stay in place. A completed backup includes metadata (`Backup Complete.json`). Choose a location outside the game installation and confirm the copy succeeded.

### 5 — Restore a backup
Select a previously completed backup folder containing `Backup Complete.json`. The toolkit checks its contents, displays the destination and asks you to type **RESTORE** to confirm. It asks where to save a recovery copy of the current folders, stages the restored data and then replaces the selected live folders. Previous folders are also renamed for recovery. Restoring an older backup can undo newer AddOn or setting changes; review the game version and paths carefully.

## Diagnostics (green button)
### 6 — Diagnostics Center (green; read-only)
**What it does:** Offers a quick health check, full diagnostic scan and export of results. Checks include the game executable and directories, disk space, processes, AddOn structure and configuration. The full scan adds cache size, log filenames, graphics adapters, a limited sample of Windows Application errors and a Battle.net DNS lookup.

**What you see:** PASS, WARN, FAIL, INFO and UNKNOWN results, a summary and **What stands out** observations.

**Reports:** Option 3 within the Diagnostics Center exports readable TXT and Markdown files to a folder **you choose** (Desktop, Documents, Downloads, browse or manual path). It can then open the destination folder. No report is exported automatically, and **no repairs are performed**. Some findings can be normal; treat them as clues, not proof of a fault.

## Repair & Reset (standard button color)
### 7 — Clear Battle.net files
Removes selected Battle.net/Blizzard launcher support-data directories under Windows ProgramData, roaming/local AppData and Temp after the relevant safety checks. It is **not** just a WoW cache clear and may reset launcher preferences or require support files to be recreated. The toolkit attempts to stop verified launcher processes; save work and close the launcher when instructed. WoW itself is not intentionally uninstalled.

### 8 — Reset AddOns and settings
Creates a verified backup of `Interface` and `WTF` at a destination you choose, then renames `Interface`, `WTF` and `Cache` so WoW can recreate them. Your AddOns, saved variables, UI layout or preferences may appear missing until restored. Close WoW first and preserve the backup.

### 9 — Clear WDB cache
Clears the contents of the selected installation's `Cache\WDB\enUS` directory when present. This is narrower than a full UI reset. The toolkit asks for confirmation; WoW can rebuild cache data.

### 10 — Rebuild game indexes
Removes selected files under `Data\indices` and matching `.idx` files so Battle.net can rebuild them. It is designed **not** to delete large `data.###` archives. A later launcher scan, repair or download may be required. Close relevant processes and follow the confirmation prompts.

### 11 — Comprehensive repair
Combines **launcher support-data cleanup (option 7)** with **WoW Interface/WTF/Cache reset (option 8)**. It creates a verified Interface/WTF backup first and asks for confirmation. This is **not** a reinstall and does **not** run every other option. Completed cleanup steps may not be automatically reversible if a later step fails.

## Other Tools (standard button color)
### 12 — Copy DirectX 11 argument
Copies `-d3d11` to the clipboard for manual use in WoW launch arguments. It does not automatically edit Battle.net settings. Remove the argument later if you want to undo the change.

### 13 — Enable admin requirement
Changes the selected WoW executable's compatibility setting so Windows requests administrator elevation when launching it. Only use this when troubleshooting a specific permission issue; elevation is not a general performance fix.

### 14 — Remove admin requirement
Removes the administrator requirement set for the selected WoW executable. Other Windows policies or compatibility settings may still cause elevation.

## Optional Support (blue button)
### 15 — Optional Ko-fi support

## Navigation
### H — Open detailed options guide
Opens `OPTIONS-README.md` from the same folder as the toolkit script. It opens the guide in Notepad, including on systems without a Markdown file association. The **Detailed Options Guide (H)** button is clickable. If the guide is missing, the toolkit displays a warning. The toolkit remains running while you read.

### 0 — Exit
Closes the main graphical toolkit window. Any separately opened repair console remains independent.

## Requirements and precautions
- Windows 10 or 11 with **Windows PowerShell 5.1** (built in). The BAT launcher invokes `powershell.exe`, not PowerShell 7 (`pwsh.exe`). No Python, Git, PowerShell 7 or third-party modules are required. To verify, open Windows PowerShell and run `$PSVersionTable.PSVersion` (expect `Major` 5, `Minor` 1).
- Extract all files from the ZIP; keep the BAT, **both PS1 scripts**, and `OPTIONS-README.md` in the same folder.
- The graphical launcher does not require elevation at startup; the original repair engine may request administrator approval when an action is launched.
- The BAT launcher uses a process-only execution-policy bypass; organization security settings can still block unsigned scripts. Review the source before running it.
- Close WoW and Battle.net as instructed; keep the toolkit console open until you exit.
- Back up `Interface`, `WTF`, `Screenshots` and other important files before changing anything.
- No repair is guaranteed to resolve every problem. Read the prompts and maintain backups.

## Optional Ko-fi support

Optional Support asks before opening <img src="https://cdn.simpleicons.org/kofi/FF5E5B" width="17" height="17" alt="Ko-fi"> [https://ko-fi.com/rebeltortuga](https://ko-fi.com/rebeltortuga) in your browser. All features remain free, and no payment information is collected by the toolkit.
