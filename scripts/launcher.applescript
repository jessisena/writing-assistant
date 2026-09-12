-- Writing Assistant launcher
-- Starts uvicorn via serve.sh, then opens the installed Chrome PWA.
-- __PROJECT_DIR__ is replaced at build time by build_launcher.sh.

set projectDir to "__PROJECT_DIR__"
set serveScript to projectDir & "/scripts/serve.sh"
set pwaPath to (POSIX path of (path to home folder)) & "Applications/Chrome Apps/Writing Assistant.app"

-- Start (or confirm already running) the server
set httpCode to ""
try
  set httpCode to do shell script "bash " & quoted form of serveScript
on error errMsg
  display dialog "Writing Assistant could not start:" & return & errMsg buttons {"OK"} default button "OK" with icon stop
  return
end try

-- Warn if the claude CLI is missing (server is up but will return 503)
if httpCode is "503" then
  display dialog "Writing Assistant started, but the claude CLI was not found on PATH." & return & return & "Install or re-authenticate the CLI, then try again." buttons {"OK"} default button "OK" with icon caution
end if

-- Open the installed PWA, or fall back to a Chrome --app window
tell application "Finder"
  if exists POSIX file pwaPath then
    do shell script "open -a " & quoted form of pwaPath
  else
    do shell script "open -na 'Google Chrome' --args --app=http://127.0.0.1:8765"
  end if
end tell
