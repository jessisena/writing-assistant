-- Writing Assistant launcher
-- Starts the pywebview desktop app (server + native window in one process).
-- __PROJECT_DIR__ is replaced at build time by build_launcher.sh.

set projectDir to "__PROJECT_DIR__"
set cmd to "cd " & quoted form of projectDir & " && PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" uv run python -m assistant.desktop"

try
  do shell script cmd
on error errMsg
  display dialog "Writing Assistant could not start:" & return & errMsg buttons {"OK"} default button "OK" with icon stop
end try
