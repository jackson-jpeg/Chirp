#!/usr/bin/env bash
# Deploy chirpchirps.com from this repo (run on the VPS, as root): bash site-deploy/deploy.sh
#
# 1. Copy checks on site/: no em dash in any page, no App Store link (nothing is on sale
#    until 2.0 ships; put the link back in the same change that ships it).
# 2. The release list signup (site-deploy/signup/): server, units, nginx rate limit zone.
# 3. nginx: site-deploy/nginx.conf replaces /etc/nginx/sites-available/chirpchirps; nginx -t,
#    and the old file goes back if the test fails. Reloaded under hub-lock prod-restart.
# 4. site/ to /root/chirpchirps-site (rsync --delete; a tarball of the old tree is kept in
#    /root/chirpchirps-site-backups/, newest 5).
# 5. Live checks: the page, the signup answering, and no App Store link served.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
site="$repo/site"
live=/root/chirpchirps-site
conf=/etc/nginx/sites-available/chirpchirps

echo "▸ copy checks"
if grep -rln $'—' --include=*.html "$site"; then echo "REFUSED: em dash in the pages above" >&2; exit 1; fi
if grep -rlnE 'apps\.apple\.com|itunes\.apple\.com' --include=*.html "$site"; then
    echo "REFUSED: App Store link in the pages above (nothing is on sale yet)" >&2; exit 1
fi
# Every page folder (<name>/index.html) is in the sitemap, and robots.txt points at it.
for page in "$site"/*/index.html; do
    name="$(basename "$(dirname "$page")")"
    grep -q "<loc>https://chirpchirps.com/$name/</loc>" "$site/sitemap.xml" ||
        { echo "REFUSED: /$name/ is missing from site/sitemap.xml" >&2; exit 1; }
done
grep -q '^Sitemap: https://chirpchirps.com/sitemap.xml$' "$site/robots.txt" ||
    { echo "REFUSED: site/robots.txt does not name the sitemap" >&2; exit 1; }
python3 -I -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$site/sitemap.xml"

echo "▸ signup service"
s="$here/signup"
python3 -I -m py_compile "$s/signup_server.py"
install -d /srv/chirpchirps
install -m 644 "$s/signup_server.py" /srv/chirpchirps/signup_server.py
install -m 755 "$s/signup_backup.sh" /srv/chirpchirps/signup_backup.sh
install -m 644 "$s/chirpchirps-signup.service" "$s/chirpchirps-backup.service" "$s/chirpchirps-backup.timer" /etc/systemd/system/
install -m 644 "$s/nginx-limits.conf" /etc/nginx/conf.d/chirpchirps-limits.conf
systemctl daemon-reload
systemctl enable --now chirpchirps-signup.service chirpchirps-backup.timer
systemctl restart chirpchirps-signup.service
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS http://127.0.0.1:3330/api/health >/dev/null 2>&1 && break; sleep 0.5; done
curl -fsS http://127.0.0.1:3330/api/health; echo

echo "▸ nginx"
old=$(mktemp)
cp -p "$conf" "$old"
install -m 644 "$here/nginx.conf" "$conf"
if ! nginx -t 2>&1 | grep -q 'test is successful'; then
    nginx -t || true
    cp -p "$old" "$conf"; rm -f "$old"
    echo "REFUSED: nginx -t failed; the old config is back" >&2; exit 1
fi
rm -f "$old"
hub-lock prod-restart --label "chirpchirps.com nginx reload" -- systemctl reload nginx

echo "▸ site"
install -d -m 700 /root/chirpchirps-site-backups
tar -czf "/root/chirpchirps-site-backups/site-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" -C /root chirpchirps-site
ls -1t /root/chirpchirps-site-backups/site-*.tar.gz | tail -n +6 | while read -r f; do rm -f -- "$f"; done
rsync -a --delete "$site/" "$live/"

echo "▸ live checks"
page=$(curl -fsS https://chirpchirps.com/)
grep -q 'Coming to iPhone' <<<"$page" || { echo "FAIL: live page lacks the new CTA" >&2; exit 1; }
if grep -qE 'apps\.apple\.com' <<<"$page"; then echo "FAIL: live page still links the App Store" >&2; exit 1; fi
# A reload swaps nginx's workers in the background: give it a few seconds.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Accept: application/json' --data 'email=not-an-address' https://chirpchirps.com/api/signup)
    [ "$code" = 400 ] && break; sleep 1
done
[ "$code" = 400 ] || { echo "FAIL: signup answered $code to a bad address (want 400)" >&2; exit 1; }
curl -fsS -o /dev/null https://chirpchirps.com/thanks.html
www=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' https://www.chirpchirps.com/support/)
[ "$www" = "301 https://chirpchirps.com/support/" ] || { echo "FAIL: www answered '$www' (want a 301 to chirpchirps.com)" >&2; exit 1; }
curl -fsS https://chirpchirps.com/robots.txt | grep -q '^Sitemap: ' || { echo "FAIL: robots.txt not served" >&2; exit 1; }
curl -fsS https://chirpchirps.com/sitemap.xml | grep -q '<urlset' || { echo "FAIL: sitemap.xml not served" >&2; exit 1; }
echo "deployed"
