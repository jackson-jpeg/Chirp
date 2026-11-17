#!/usr/bin/env bash
# Nightly backup of chirpchirps.com's signup list (run by chirpchirps-backup.timer).
# A consistent SQLite copy into /var/backups/chirpchirps (newest 14 kept, mode 600),
# verified by opening it and comparing the row count, then a copy to the Mac's
# ~/Downloads/chirpchirps-signup-backups (newest 3) when the Mac is reachable.
# The Mac being asleep is normal: the next night tries again. A failed local
# backup pages once (tag chirpchirps-backup).
set -euo pipefail
DB=${SIGNUP_DB:-/var/lib/private/chirpchirps/signups.db}
OUT=${BACKUP_DIR:-/var/backups/chirpchirps}
MAC=${BACKUP_MAC-macbook}
MACDIR=Downloads/chirpchirps-signup-backups
PAGE=${BACKUP_PAGE:-ops-page}
stamp=$(date -u +%Y-%m-%dT%H%MZ)
dst="$OUT/signups-$stamp.db"
fail() { "$PAGE" --tag chirpchirps-backup "chirpchirps.com: signup backup failed" "$1" || true; echo "FAIL: $1" >&2; exit 1; }
[ -f "$DB" ] || fail "no database at $DB"
install -d -m 700 "$OUT"
umask 077
python3 -I - "$DB" "$dst" <<'PY' || fail "could not copy or verify the database"
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
a = src.execute("SELECT COUNT(*) FROM signups").fetchone()[0]
b = dst.execute("SELECT COUNT(*) FROM signups").fetchone()[0]
ok = dst.execute("PRAGMA integrity_check").fetchone()[0]
dst.close(); src.close()
if a != b or ok != "ok":
    sys.exit(f"rows {a} vs {b}, integrity {ok}")
print(f"backed up {b} signup(s)")
PY
# keep the newest 14
ls -1t "$OUT"/signups-*.db | tail -n +15 | while read -r old; do rm -f -- "$old"; done
if [ -n "$MAC" ]; then
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$MAC" "mkdir -p $MACDIR && chmod 700 $MACDIR" 2>/dev/null \
       && scp -q -o ConnectTimeout=10 "$dst" "$MAC:$MACDIR/"; then
        want=$(sha256sum "$dst" | cut -d' ' -f1)
        got=$(ssh -o ConnectTimeout=10 "$MAC" "shasum -a 256 $MACDIR/$(basename "$dst")" | cut -d' ' -f1)
        if [ "$want" = "$got" ]; then
            # keep the newest 3 on the Mac: list there, decide here, delete by name (our own folder only)
            ssh -o ConnectTimeout=10 "$MAC" "ls -1 $MACDIR" > "$OUT/.mac-list" || true
            grep -E '^signups-[0-9TZ:-]+\.db$' "$OUT/.mac-list" | sort -r | tail -n +4 | while read -r old; do
                ssh -o ConnectTimeout=10 "$MAC" "rm -f $MACDIR/$old"
            done
            rm -f "$OUT/.mac-list"
            echo "Mac copy verified"
        else
            echo "WARN: Mac copy checksum mismatch; kept on the VPS" >&2
        fi
    else
        echo "WARN: Mac not reachable; kept on the VPS, retried next run" >&2
    fi
fi
