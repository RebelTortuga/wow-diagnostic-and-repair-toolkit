Option Explicit
Dim shell, files, folder, scriptPath, powershellPath, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
scriptPath = files.BuildPath(folder, "WoWToolkit-Sidebar.ps1")
If Not files.FileExists(scriptPath) Then
    MsgBox "WoWToolkit-Sidebar.ps1 is missing. Extract all files into the same folder.", 16, "WoW Toolkit"
    WScript.Quit 1
End If
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = Chr(34) & powershellPath & Chr(34) & " -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34)
shell.Run command, 0, False
