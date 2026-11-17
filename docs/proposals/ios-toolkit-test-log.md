# Proposal for ios-toolkit: keep the cause when `ios test` runs no tests

Written 2026-11-17 by a Chirp session. Not applied: committing it to ios-toolkit was refused
by the permission check, and the toolkit is not this repo's. The toolkit owner's call.

## What happened

`ios test chirp --only ChirpUITests ...` printed only:

    ios: NO TESTS RAN. That is not a pass — check the -only-testing filter
    ios: and whether the bundle compiled.

`ios build chirp` on the same tree succeeded, so it was not a compile error. The cause was
lost in two places:

1. `cmd_test` pipes xcodebuild through `xcbeautify --quiet`, which drops every line it does not
   recognise, including xcodebuild's own `xcodebuild: error: ...` and `Testing failed:` blocks.
2. The raw log (`LOG=$(mktemp)`) is deleted on that path before anything else reads it.

Reading the partial result bundle by hand showed xcodebuild had gone to `simctl_diagnostics`
(a Simulator-side failure), and that gathering them hit "No space left on device" on the Mac.

## The change (bin/ios, the NO TESTS RAN branch of the remote script in `cmd_test`)

```sh
  echo "ios: NO TESTS RAN. That is not a pass — check the -only-testing filter" >&2
  echo "ios: and whether the bundle compiled." >&2
  # xcbeautify --quiet drops lines it does not recognise, which includes
  # xcodebuild's own "xcodebuild: error: ..." and "Testing failed:" blocks.
  echo "ios: xcodebuild's last error lines:" >&2
  grep -nE 'error|Error|failed|Failed|Testing cancelled|\*\* TEST' "$LOG" | tail -25 >&2
  echo "ios: xcodebuild's last lines:" >&2
  tail -15 "$LOG" >&2
  rm -f "$LOG"; exit 1
```

Checked: `bash -n bin/ios` passes and `tests/sim-for-app.test.sh` passes with it applied; it
was then reverted.

## Worth considering too

Simulator runs do not pass `-collect-test-diagnostics never` (device runs do, for the same
reason: a ~760 MB archive filled the Mac on 2026-09-25). The Chirp run's diagnostics were 378 MB
and ran the disk out. Passing it for simulator runs as well would keep a failed run from
filling the Mac; the test's own attachments are unaffected.
