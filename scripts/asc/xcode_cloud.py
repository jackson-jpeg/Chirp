#!/usr/bin/env python3
"""Xcode Cloud for ChirpChirps 2.0 through the App Store Connect API (VPS; the key stays on the Mac).

    scripts/asc/xcode_cloud.py status                 # product, repository, workflows, this month's hours
    scripts/asc/xcode_cloud.py setup [--dry-run]      # make or correct the two workflows (manual start only)
    scripts/asc/xcode_cloud.py start testflight|tests [--branch master]
    scripts/asc/xcode_cloud.py hours                  # log every finished run's compute time

Ported from LeftSaid's (/root/LeftSaid/scripts/asc/xcode_cloud.py), itself from Sim Sunday's.
Mac disk policy (Jackson, 2026-11-17, CLAUDE.md): Xcode Cloud FIRST for builds and simulator
tests; the Mac is the fallback when the hours run out.
Jackson's rules (2026-11-15): free tier only, never upgrade; the 25 compute hours a month are
shared by all his apps, so use them for archives, uploads and release-gate runs, not every
small change; workflows start by hand only, never on a push; Xcode Cloud email off; check the
hours left before each run and report the hours used. `start` refuses at 20 hours counted
across every app's log (the hours are shared).

Workflows: "TestFlight" (archive scheme Chirp, App Store eligible; nothing here submits)
and "Tests" (the Chirp scheme's tests: ChirpCoreTests and ChirpUITests, on iPhone 17 Pro Max).
v2/ci_scripts/ci_post_clone.sh generates v2/ChirpChirps.xcodeproj (XcodeGen; it is not in git).
v2 already signs automatically, so nothing is rewritten.

What the API can't do (Xcode or the web only, Jackson's clicks): create the product and
connect GitHub, the email switch, and the next build number. The API has no usage figure:
`hours` sums each run's action times; check the first runs against App Store Connect ->
Xcode Cloud -> Usage.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import time

APP_ID = '6761436901'
# The Mac moves to Xcode 27 (2026-11-17); match it. Override with XCODE_CLOUD_XCODE; a name
# Xcode Cloud does not offer fails and lists the ones it does.
XCODE_NAME = os.environ.get('XCODE_CLOUD_XCODE', 'Xcode 27.1')
SIM_DEVICE = 'iPhone 17 Pro Max'
CONTAINER = 'v2/ChirpChirps.xcodeproj'   # from the repo root
SCHEME = 'Chirp'
BRANCHES = ('master',)   # manual starts allowed on these only
HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.environ.get('XCODE_CLOUD_LOG', os.path.join(HERE, '..', '..', 'docs', 'xcode-cloud-hours.tsv'))
SHARED_LOGS = [LOG, '/root/simsunday/docs/handoff/xcode-cloud-hours.tsv',   # every app's runs count
               '/root/LeftSaid/docs/rebuild/xcode-cloud-hours.tsv',
               '/root/crease-cracker/docs/xcode-cloud-hours.tsv']
WARN_HOURS = 20.0
FREE_HOURS = 25.0
START_KEYS = ('branchStartCondition', 'tagStartCondition', 'pullRequestStartCondition', 'scheduledStartCondition',
              'manualBranchStartCondition', 'manualTagStartCondition', 'manualPullRequestStartCondition')

MAC_HOST = os.environ.get('ASC_MAC_HOST', 'macbook-tunnel')
MAC_DIR = 'Chirp/scripts/asc'   # asc-api.rb there reads ~/.sanger-build (the key never leaves the Mac)
SSH = ['ssh', '-o', 'ConnectTimeout=20', '-o', 'BatchMode=yes', MAC_HOST]
SCP = ['scp', '-q', '-o', 'ConnectTimeout=20', '-o', 'BatchMode=yes']
DRY_RUN = False
_seq = 0


class AscError(Exception):
    pass


def die(msg, code=1):
    print(f'FAIL: {msg}', file=sys.stderr, flush=True)
    sys.exit(code)


def log(msg):
    print(msg, flush=True)


def _ssh(remote, timeout=180):
    return subprocess.run(SSH + [remote], capture_output=True, text=True, timeout=timeout)


def asc(method, path, body=None, ok=(200, 201, 204), retries=3):
    """Returns (status, json). Never writes to a submission endpoint; a write is never retried."""
    global _seq
    method = method.upper()
    if not path.startswith('/v') or "'" in path:
        raise AscError(f'refusing odd path {path!r}')
    if method != 'GET' and re.search(r'submission', path, re.I):
        raise AscError(f'REFUSED: {method} {path} is a submission endpoint; this script never submits')
    if method != 'GET' and DRY_RUN:
        log(f'  DRY-RUN skip {method} {path}' + (f'  body={json.dumps(body)[:600]}' if body else ''))
        return None, None
    remote_body = None
    if body is not None:
        _seq += 1
        remote_body = f'xc-body-{os.getpid()}-{_seq}.json'
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            json.dump(body, f)
            local = f.name
        try:
            r = subprocess.run(SCP + [local, f'{MAC_HOST}:{MAC_DIR}/{remote_body}'], capture_output=True, text=True, timeout=120)
        finally:
            os.unlink(local)
        if r.returncode != 0:
            raise AscError(f'scp of request body failed: {r.stderr.strip()}')
    remote = f"cd ~/{MAC_DIR} && ruby asc-api.rb {method} '{path}'" + (f' - < {remote_body}' if remote_body else '')
    last = ''
    try:
        for i in range(retries if method == 'GET' else 1):
            try:
                r = _ssh(remote)
            except subprocess.TimeoutExpired:
                last = 'ssh timed out'
                continue
            if r.returncode != 0 or not r.stdout.startswith('HTTP '):
                last = f'ssh rc={r.returncode} {r.stderr.strip()[:300]} {r.stdout[:300]}'
                time.sleep(10)
                continue
            first, _, rest = r.stdout.partition('\n')
            code = int(first.split()[1])
            try:
                data = json.loads(rest) if rest.strip() else None
            except ValueError:
                data = {'raw': rest}
            if code not in ok:
                errs = (data or {}).get('errors') if isinstance(data, dict) else None
                detail = '; '.join(f"{e.get('code')}: {e.get('detail')}" for e in errs) if errs else str(data)[:500]
                raise AscError(f'{method} {path} -> HTTP {code}: {detail}')
            return code, data
        raise AscError(f'{method} {path}: Mac unreachable or API call failed ({last})')
    finally:
        if remote_body:
            _ssh(f'rm -f ~/{MAC_DIR}/{remote_body}', timeout=60)


def product_and_repo():
    try:
        _, d = asc('GET', f'/v1/apps/{APP_ID}/ciProduct')
    except AscError as e:
        if 'HTTP 404' in str(e):
            return None, None
        raise
    prod = (d or {}).get('data')
    if not prod:
        return None, None
    _, r = asc('GET', f"/v1/ciProducts/{prod['id']}/primaryRepositories")
    return prod, (r['data'][0] if r['data'] else None)


def need_product():
    prod, repo = product_and_repo()
    if not prod or not repo:
        die("no Xcode Cloud product or repository for ChirpChirps yet: Jackson's onboarding click first "
            '(docs/xcode-cloud.md)')
    return prod, repo


def xcode_and_macos():
    _, d = asc('GET', '/v1/ciXcodeVersions?limit=50&include=macOsVersions')
    x = next((v for v in d['data'] if v['attributes']['name'] == XCODE_NAME), None)
    if not x:
        offered = ', '.join(v['attributes']['name'] for v in d['data'])
        die(f'{XCODE_NAME} is not offered by Xcode Cloud (offered: {offered}); set XCODE_CLOUD_XCODE')
    macs = x['relationships']['macOsVersions']['data']
    if not macs:
        die(f'no macOS version listed for {XCODE_NAME}')
    return x, macs[0]['id']


def destination(xcode):
    for t in xcode['attributes']['testDestinations']:
        if t['deviceTypeName'] == SIM_DEVICE:
            rt = sorted(t['availableRuntimes'], key=lambda r: [int(p) for p in r['runtimeName'].split()[-1].split('.')])[-1]
            return {'deviceTypeName': t['deviceTypeName'], 'deviceTypeIdentifier': t['deviceTypeIdentifier'],
                    'runtimeName': rt['runtimeName'], 'runtimeIdentifier': rt['runtimeIdentifier'], 'kind': 'SIMULATOR'}
    die(f'{SIM_DEVICE} is not a test destination for {XCODE_NAME}')


def manual_only():
    c = {k: None for k in START_KEYS}
    c['manualBranchStartCondition'] = {'source': {'isAllMatch': False,
                                                  'patterns': [{'pattern': b, 'isPrefix': False} for b in BRANCHES]}}
    return c


def workflow_specs(dest):
    return {
        'TestFlight': {
            'description': 'Archive and upload for TestFlight. Manual start only. Never submits.',
            'actions': [{'name': 'Archive - iOS', 'actionType': 'ARCHIVE', 'destination': 'ANY_IOS_DEVICE',
                         'buildDistributionAudience': 'APP_STORE_ELIGIBLE', 'scheme': SCHEME,
                         'platform': 'IOS', 'isRequiredToPass': True}],
        },
        'Tests': {
            'description': "The Chirp scheme's tests (ChirpCore and UI). Manual start only (release gates, not every change).",
            'actions': [{'name': 'Unit tests', 'actionType': 'TEST', 'scheme': SCHEME, 'platform': 'IOS',
                         'isRequiredToPass': True,
                         'testConfiguration': {'kind': 'USE_SCHEME_SETTINGS', 'testDestinations': [dest]}}],
        },
    }


def workflows(prod_id):
    return asc('GET', f'/v1/ciProducts/{prod_id}/workflows?limit=50')[1]['data']


def automatic_starts(w):
    return [k for k in START_KEYS if k != 'manualBranchStartCondition' and w['attributes'].get(k)]


def read_log(path):
    rows = []
    if os.path.exists(path):
        for line in open(path):
            if line.startswith('#') or not line.strip():
                continue
            run_id, number, workflow, finished, minutes = line.rstrip('\n').split('\t')[:5]
            rows.append({'id': run_id, 'number': number, 'workflow': workflow, 'finished': finished, 'minutes': float(minutes)})
    return rows


def month_hours(rows, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    return sum(r['minutes'] for r in rows if r['finished'][:7] == now.strftime('%Y-%m')) / 60


def shared_month_hours():
    return sum(month_hours(read_log(p)) for p in SHARED_LOGS)


def cmd_status(_):
    prod, repo = product_and_repo()
    if not prod:
        print("product: none (Jackson's onboarding click not done: docs/xcode-cloud.md)")
    else:
        print(f"product: {prod['id']} {prod['attributes'].get('name')}")
        print(f"repository: {repo['id'] if repo else 'none'} {(repo or {}).get('attributes', {}).get('repositoryName', '')}")
        for w in workflows(prod['id']):
            bad = automatic_starts(w)
            print(f"workflow: {w['attributes']['name']} {w['id']} enabled={w['attributes'].get('isEnabled')} "
                  f"{'AUTOMATIC START: ' + ','.join(bad) if bad else 'manual only'}")
    print(f'this month: ChirpChirps {month_hours(read_log(LOG)):.2f} h, all apps {shared_month_hours():.2f} '
          f'of {FREE_HOURS:.0f} free compute hours logged')


def cmd_setup(args):
    global DRY_RUN
    DRY_RUN = args.dry_run
    prod, repo = need_product()
    xcode, macos_id = xcode_and_macos()
    dest = destination(xcode)
    specs = workflow_specs(dest)
    have = {w['attributes']['name']: w for w in workflows(prod['id'])}
    for name, spec in specs.items():
        attrs = {'name': name, 'description': spec['description'], 'actions': spec['actions'],
                 'containerFilePath': CONTAINER, 'isEnabled': True, 'isLockedForEditing': False, 'clean': False,
                 **manual_only()}
        rel = {'xcodeVersion': {'data': {'type': 'ciXcodeVersions', 'id': xcode['id']}},
               'macOsVersion': {'data': {'type': 'ciMacOsVersions', 'id': macos_id}}}
        if name in have:
            asc('PATCH', f"/v1/ciWorkflows/{have[name]['id']}",
                {'data': {'type': 'ciWorkflows', 'id': have[name]['id'], 'attributes': attrs, 'relationships': rel}})
            log(f'updated {name}')
        else:
            rel.update({'product': {'data': {'type': 'ciProducts', 'id': prod['id']}},
                        'repository': {'data': {'type': 'scmRepositories', 'id': repo['id']}}})
            asc('POST', '/v1/ciWorkflows', {'data': {'type': 'ciWorkflows', 'attributes': attrs, 'relationships': rel}})
            log(f'created {name}')
    # Xcode's onboarding makes a "Default" workflow that starts on every push: disable any other.
    for name, w in have.items():
        if name not in specs and (w['attributes'].get('isEnabled') or automatic_starts(w)):
            asc('PATCH', f"/v1/ciWorkflows/{w['id']}",
                {'data': {'type': 'ciWorkflows', 'id': w['id'], 'attributes': {'isEnabled': False, **manual_only()}}})
            log(f'disabled {name} (not one of ours)')
    if not DRY_RUN:
        for w in workflows(prod['id']):
            if w['attributes'].get('isEnabled') and automatic_starts(w):
                die(f"read back: {w['attributes']['name']} can still start on its own: {automatic_starts(w)}")
        log('read back: every enabled workflow starts by hand only')


def cmd_start(args):
    prod, repo = need_product()
    name = {'testflight': 'TestFlight', 'tests': 'Tests'}[args.which]
    w = next((w for w in workflows(prod['id']) if w['attributes']['name'] == name), None)
    if not w:
        die(f'no workflow {name!r}: run setup first')
    used = shared_month_hours()
    log(f'hours before this run: {used:.2f} of {FREE_HOURS:.0f} used this month (all apps), {FREE_HOURS - used:.2f} left')
    if used >= WARN_HOURS:
        die(f"{used:.1f} h logged this month across all apps (line {WARN_HOURS:.0f} of {FREE_HOURS:.0f}): not starting without Jackson's okay")
    _, refs = asc('GET', f"/v1/scmRepositories/{repo['id']}/gitReferences?limit=200")
    ref = next((r for r in refs['data'] if r['attributes'].get('kind') == 'BRANCH'
                and r['attributes'].get('name') == args.branch and not r['attributes'].get('isDeleted')), None)
    if not ref:
        die(f'branch {args.branch!r} not found in the repository')
    _, run = asc('POST', '/v1/ciBuildRuns', {'data': {'type': 'ciBuildRuns', 'attributes': {'clean': False},
                 'relationships': {'workflow': {'data': {'type': 'ciWorkflows', 'id': w['id']}},
                                   'sourceBranchOrTag': {'data': {'type': 'scmGitReferences', 'id': ref['id']}}}}})
    log(f"started {name} run {run['data']['attributes'].get('number')} ({run['data']['id']}) on {args.branch}")


def parse(t):
    return dt.datetime.fromisoformat(t.replace('Z', '+00:00')) if t else None


def run_minutes(run_id):
    """Sum of the run's actions' own run times (each action is its own machine)."""
    total = 0.0
    for a in asc('GET', f'/v1/ciBuildRuns/{run_id}/actions?limit=50')[1]['data']:
        s, f = parse(a['attributes'].get('startedDate')), parse(a['attributes'].get('finishedDate'))
        if s and f:
            total += (f - s).total_seconds() / 60
    return total


def cmd_hours(_):
    prod, _repo = need_product()
    seen = {r['id'] for r in read_log(LOG)}
    names = {w['id']: w['attributes']['name'] for w in workflows(prod['id'])}
    _, d = asc('GET', f"/v1/ciProducts/{prod['id']}/buildRuns?limit=200&include=workflow")
    new = []
    for r in d['data']:
        a = r['attributes']
        if r['id'] in seen or a.get('executionProgress') != 'COMPLETE':
            continue
        wid = (((r.get('relationships') or {}).get('workflow') or {}).get('data') or {}).get('id')
        new.append((r['id'], str(a.get('number')), names.get(wid, '?'), a.get('finishedDate') or '', run_minutes(r['id'])))
    if new:
        exists = os.path.exists(LOG)
        with open(LOG, 'a') as f:
            if not exists:
                f.write('# run id\tnumber\tworkflow\tfinished (UTC)\tcompute minutes (sum of actions)\n')
            for row in sorted(new, key=lambda x: x[3]):
                f.write('\t'.join([row[0], row[1], row[2], row[3], f'{row[4]:.1f}']) + '\n')
                print(f'logged run {row[1]} {row[2]}: {row[4]:.1f} min')
    used = shared_month_hours()
    print(f'this month: ChirpChirps {month_hours(read_log(LOG)):.2f} h, all apps {used:.2f} of {FREE_HOURS:.0f}')
    if used >= WARN_HOURS:
        print(f'WARN: over {WARN_HOURS:.0f} hours this month across all apps: tell Jackson', file=sys.stderr)
        sys.exit(2)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('status')
    s = sub.add_parser('setup'); s.add_argument('--dry-run', action='store_true')
    s = sub.add_parser('start'); s.add_argument('which', choices=['testflight', 'tests']); s.add_argument('--branch', default=BRANCHES[0])
    sub.add_parser('hours')
    a = p.parse_args()
    {'status': cmd_status, 'setup': cmd_setup, 'start': cmd_start, 'hours': cmd_hours}[a.cmd](a)


if __name__ == '__main__':
    main()
