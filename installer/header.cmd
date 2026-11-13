@echo off
rem AI Usage Widget - single file (portable or installer). https://github.com/jbjmanse-hub/ai-usage-widget
rem This file contains a PowerShell installer and the zipped app (base64) after the markers below.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$f='%~f0'; $t=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8); $a=$t.IndexOf('#'+'INSTALLER#'); $b=$t.IndexOf('#'+'PAYLOAD#'); & ([scriptblock]::Create($t.Substring($a, $b-$a))) $f $t.Substring($b+9).Trim()"
exit /b
