#!/usr/bin/env python3
"""phase-02..phase-05 static verification (no Dart SDK in sandbox).

1. Bracket/paren/brace balance per .dart file, string & comment aware
   (now also the phase-03 capture Dart files and the capture .kt files,
   with a Kotlin-aware stripper).
2. Regex literals (r'...') compile-checked with Python re (approximate
   Dart RegExp compatibility check), multi-part concatenations joined.
3. Banned/leftover patterns from known bug classes.
4. phase-02 headers on phase-02 files; phase-03 headers on capture files.
5. Test-count estimate.
6. phase-03 capture contract: channel/method/string parity between the
   Kotlin sources and the Dart constants, manifest declarations, WAL
   file names, allowlist asset validity + wiring, Kotlin symbol
   cross-references (CaptureLog, WalWriter, companion state) and the
   l10n key parity between the delegate and both .arb files.
6l. phase-04 capture-II contract: play-flavor SMS purity (no receiver/
   permissions in play), power receiver wiring, WAL SMS line shape,
   new routes, new pubspec deps, gradle test wiring, and the Kotlin
   import allow-list extension for the power source set.
6n. phase-05 survival contract: survival channel parity (11 methods),
   watchdog cadences + pref keys, keep-alive rules (specialUse, 15-min
   heartbeat, no stopSelf in onTaskRemoved), battery-permission flavor
   split, workmanager pin + KEEP/battery-not-low/backoff wiring, and
   l10n survival-getter sanity (unique names, en+hi branches).
"""
import json
import re
import sys
from pathlib import Path

files = sorted(
    list(Path('lib/data').rglob('*.dart')) +
    list(Path('test/data').rglob('*.dart')) +
    [Path('lib/main.dart')],
)
capture_dart = sorted(
    list(Path('lib/features/capture').rglob('*.dart')) +
    list(Path('test/features/capture').rglob('*.dart')) +
    [Path('test/app_smoke_test.dart')],
)
capture_kt = sorted(
    Path('android/app/src/main/kotlin/in/udao/app/capture').glob('*.kt')
)
# phase-04: the power source set carries the SMS receiver (glue only;
# pure logic stays in main so unit tests cover every variant).
power_kt = sorted(
    Path('android/app/src/power/kotlin/in/udao/app/capture').glob('*.kt')
)
# phase-05: the survival feature set (Dart + Kotlin) and its tests.
survival_dart = sorted(
    list(Path('lib/features/survival').rglob('*.dart')) +
    list(Path('test/features/survival').rglob('*.dart'))
)
survival_kt = sorted(
    Path('android/app/src/main/kotlin/in/udao/app/survival').glob('*.kt')
)
# phase-06: the on-device AI stack + chat + AI settings + tests.
ai_dart = sorted(
    list(Path('lib/features/ai').rglob('*.dart')) +
    list(Path('lib/features/chat').rglob('*.dart')) +
    list(Path('test/features/ai').rglob('*.dart')) +
    list(Path('test/features/chat').rglob('*.dart')) +
    [Path('lib/features/settings/ai_settings_screen.dart')]
)
ai_kt = sorted(
    Path('android/app/src/main/kotlin/in/udao/app/ai').glob('*.kt')
)
errors = []

Q3D = "'''"
Q3S = '"""'


def strip_dart(src):
    """Replace strings/comments with spaces (keep newlines)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append('\n' if j < n else '')
            i = j
        elif src.startswith('/*', i):
            j = src.find('*/', i)
            j = n if j < 0 else j + 2
            out.append('\n' * src.count('\n', i, j))
            i = j
        elif src[i:i + 3] in (Q3D, Q3S):
            q = src[i:i + 3]
            j = src.find(q, i + 3)
            j = n if j < 0 else j + 3
            out.append('\n' * src.count('\n', i, j))
            i = j
        elif src[i] in ("'", '"'):
            # String literal. `$` starts simple interpolation; `${`
            # opens a brace-nested block that may itself contain
            # string literals (and quotes) — track depth.
            q = src[i]
            j = i + 1
            depth = []
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if depth:
                    if src[j] == '{' and src[j - 1] == r'$':
                        depth.append('{')
                    elif src[j] == q and not depth[-1] == 'braced':
                        pass
                    if src[j] == '}':
                        depth.pop()
                    j += 1
                    continue
                if src.startswith(r'${', j):
                    depth.append('braced')
                    j += 2
                    continue
                if src[j] == r'$' and j + 1 < n and src[j + 1] != q:
                    j += 2  # skip simple $id (next char is id start)
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            out.append(' ')
            i = j
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)


# ---- 1. balance ----
def check_balance(path, code):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    bad = False
    for idx, ch in enumerate(code):
        if ch in '([{':
            stack.append((ch, code.count('\n', 0, idx) + 1))
        elif ch in ')]}':
            if not stack or stack[-1][0] != pairs[ch]:
                line = code.count('\n', 0, idx) + 1
                errors.append(f'{path}:{line}: unbalanced {ch}')
                bad = True
                break
            stack.pop()
    if not bad and stack:
        errors.append(
            f'{path}: unclosed {stack[-1][0]} from line {stack[-1][1]}')


def strip_kotlin(src):
    """Kotlin-aware stripper: //, /* */ and "...\" with ${...} template
    tracking (templates may nest quotes); triple-quoted strings too."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            i = j
        elif src.startswith('/*', i):
            j = src.find('*/', i)
            j = n if j < 0 else j + 2
            out.append('\n' * src.count('\n', i, j))
            i = j
        elif src[i:i + 3] == '"""':
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append('\n' * src.count('\n', i, j))
            i = j
        elif src[i] == '"':
            j = i + 1
            depth = 0
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src.startswith('${', j):
                    depth += 1
                    j += 2
                    continue
                if src[j] == '}' and depth > 0:
                    depth -= 1
                    j += 1
                    continue
                if src[j] == '"' and depth == 0:
                    j += 1
                    break
                j += 1
            out.append(' ')
            i = j
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)


for f in files:
    check_balance(f, strip_dart(f.read_text(encoding='utf-8')))
for f in capture_dart:
    check_balance(f, strip_dart(f.read_text(encoding='utf-8')))
for f in capture_kt + power_kt + survival_kt + ai_kt:
    check_balance(f, strip_kotlin(f.read_text(encoding='utf-8')))
for f in survival_dart + ai_dart:
    check_balance(f, strip_dart(f.read_text(encoding='utf-8')))


# ---- 2. regex literals compile ----
RAW_LIT = re.compile("(?<![A-Za-z0-9_\\\\])r('(?:[^'\\\\]|\\\\.)*')")


def try_regexes():
    count = 0
    for f in files + capture_dart:
        src = f.read_text(encoding='utf-8')
        matches = list(RAW_LIT.finditer(src))
        joined = []
        for m in matches:
            if joined:
                between = src[joined[-1][1]:m.start()]
                if re.fullmatch(r"[\s'+]+", between):
                    joined[-1] = (
                        joined[-1][0] + m.group(1)[1:-1], m.end())
                    continue
            joined.append((m.group(1)[1:-1], m.end()))
        for body, end in joined:
            ci = 'caseSensitive: false' in src[max(0, end - 300):end + 300]
            flags = re.I if ci else 0
            try:
                re.compile(body.replace("\\'", "'"), flags)
                count += 1
            except re.error as e:
                errors.append(f'{f}: regex {body[:60]!r} -> {e}')
    return count


nregex = try_regexes()

# ---- 3. banned / leftover patterns ----
banned = [
    (r'android\.Database', 'android.Database leftover'),
    (r'Money2\b', 'Money2 leftover'),
    (r'insertEntry\b', 'insertEntry leftover'),
    (r'TxnDirectionHolder', 'TxnDirectionHolder leftover'),
    (r'Result_int', 'Result_int leftover'),
    (r'_trimTail', '_trimTail leftover'),
    (r'TODO(?!-VERIFY\(local\))|FIXME', 'unfinished marker'),
    (r'\\\$[|)]', 'escaped-dollar in regex (literal $ bug)'),
    (r'CrossAxisAlignment\.stretch', 'banned stretch'),
    (r'\.apply\(', 'banned TextStyle.apply'),
    (r'Semantics\.enabled', 'banned Semantics.enabled getter'),
    (r'withOpacity\(', 'banned withOpacity'),
    # phase-06 errata: three real analyzer breakers the old checks
    # could not see.
    (r'^extension\s*<', 'type-params before extension NAME is invalid '
                        '(use `extension Name<T> on ...`)'),
    (r'^extension\s+on\s+\w+<', 'unnamed generic extension is invalid '
                                  '(name it and give it the type params)'),
    (r"as\s+[A-Za-z_]\w*\?\s*==", '`as T? ==` parses wrong — '
                                     'parenthesise the cast'),
    (r"\.warn\([^)]*',\s*error\s*:", 'UdaoLogger.warn takes ONE string '
                                        '(inline the error)'),
    (r"\.info\([^)]*',\s*error\s*:", 'UdaoLogger.info takes ONE string '
                                        '(inline the error)'),
]
for f in files + capture_dart + ai_dart:
    for ln, line in enumerate(
            f.read_text(encoding='utf-8').splitlines(), 1):
        for pat, why in banned:
            if re.search(pat, line):
                errors.append(f'{f}:{ln}: {why}: {line.strip()[:80]}')
        # bare `$` before a closing quote is a Dart syntax error — but
        # ONLY inside non-raw strings (raw strings keep it literal).
        for m in re.finditer(r"(?<!\\)\$['\"']", line):
            if "r'" not in line[:m.start()] and 'r"' not in line[:m.start()]:
                errors.append(
                    f'{f}:{ln}: bare $ before a closing quote — '
                    f'escape it (\\$): {line.strip()[:80]}')

# ---- 4. headers ----
legacy_edited = {Path('lib/main.dart'), Path('test/app_smoke_test.dart')}
for f in files:
    if f.name == 'test_db.dart' and f.parent.name == 'db':
        continue
    if f in legacy_edited:
        continue
    if not f.read_text(encoding='utf-8')[:200].startswith('// phase-02'):
        errors.append(f'{f}: missing // phase-02 header')
for f in capture_dart:
    if f in legacy_edited:
        continue
    head = f.read_text(encoding='utf-8')[:200]
    # phase-04 capture-II files carry their own header (checked in 6l);
    # phase-06 added the gemma vision leg to the receipt dir.
    if head.startswith('// phase-04') or head.startswith('// phase-06'):
        continue
    if not head.startswith('// phase-03'):
        errors.append(f'{f}: missing // phase-03 header')
for f in capture_kt + survival_kt:
    head = f.read_text(encoding='utf-8')[:200]
    # phase-04 capture-II / phase-05 (extended) files carry their own
    # headers.
    if head.startswith('// phase-04') or head.startswith('// phase-05'):
        continue
    if f in survival_kt:
        errors.append(f'{f}: missing // phase-05 header')
        continue
    if not head.startswith('// phase-03'):
        errors.append(f'{f}: missing // phase-03 header')
for f in survival_dart:
    head = f.read_text(encoding='utf-8')[:200]
    if not head.startswith('// phase-05'):
        errors.append(f'{f}: missing // phase-05 header')

# ---- 6. phase-03 capture contract ----
KDIR = Path('android/app/src/main/kotlin/in/udao/app/capture')
kt_bridge = (KDIR / 'CaptureBridge.kt').read_text(encoding='utf-8')
kt_listener = (KDIR / 'UdaoNotificationListener.kt').read_text(
    encoding='utf-8')
kt_wal = (KDIR / 'WalWriter.kt').read_text(encoding='utf-8')
kt_health = (KDIR / 'HealthPinger.kt').read_text(encoding='utf-8')
kt_boot = (KDIR / 'BootReceiver.kt').read_text(encoding='utf-8')
kt_main = Path(
    'android/app/src/main/kotlin/in/udao/app/MainActivity.kt'
).read_text(encoding='utf-8')
manifest = Path('android/app/src/main/AndroidManifest.xml').read_text(
    encoding='utf-8')
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')
gradle = Path('android/app/build.gradle.kts').read_text(encoding='utf-8')
dart_channels = Path(
    'lib/features/capture/bridge/capture_channels.dart'
).read_text(encoding='utf-8')
dart_l10n = Path('lib/l10n/app_localizations.dart').read_text(
    encoding='utf-8')


def contract(cond, msg):
    if not cond:
        errors.append(f'contract: {msg}')


# 6a. channel + method parity (Kotlin "x" vs Dart 'x')
contract('"udao/capture/stream"' in kt_bridge,
         'CaptureBridge.kt: EVENT_CHANNEL value missing')
contract('"udao/capture/control"' in kt_bridge,
         'CaptureBridge.kt: CONTROL_CHANNEL value missing')
for name in ('stream', 'control'):
    contract(
        f"static const String {name} = 'udao/capture/"
        f"{'stream' if name == 'stream' else 'control'}'" in dart_channels,
        f'capture_channels.dart: {name} const drifted')
for method in ('getWAL', 'ackWAL', 'listenerStatus', 'requestRebind',
               'openListenerSettings', 'rebindViaToggle', 'pushAllowlist'):
    contract(f'"{method}"' in kt_bridge, f'CaptureBridge.kt: {method}')
    contract(f"'{method}'" in dart_channels,
             f'capture_channels.dart: {method}')
for key in ('connected', 'lastEventAt', 'componentEnabled'):
    contract(f'"{key}"' in kt_bridge, f'status key {key} missing in Kotlin')
    contract(f"'{key}'" in Path(
        'lib/features/capture/bridge/listener_status.dart'
    ).read_text(encoding='utf-8'), f'status key {key} missing in Dart')

# 6b. WAL contract
contract('"capture_wal.jsonl"' in kt_wal, 'WalWriter.kt: WAL_FILE missing')
contract('capture_wal.$n.jsonl' in kt_wal, 'WalWriter.kt: rotation template')
for key in ('"pkg"', '"title"', '"text"', '"bigText"', '"subText"', '"ts"'):
    contract(key in kt_listener, f'listener WAL line key {key} missing')
for fn in ('WalWriter.append', 'WalWriter.readAll', 'WalWriter.ack',
           'WalWriter.ioExecutor'):
    contract(fn in kt_listener or fn in kt_bridge, f'{fn} reference missing')

# 6c. manifest + gradle + asset wiring
contract('.capture.UdaoNotificationListener' in manifest,
         'manifest: listener service missing')
contract('BIND_NOTIFICATION_LISTENER_SERVICE' in manifest,
         'manifest: listener permission missing')
contract('android.service.notification.NotificationListenerService'
        in manifest, 'manifest: service intent-filter missing')
contract('.capture.BootReceiver' in manifest, 'manifest: boot receiver')
contract('android.intent.action.BOOT_COMPLETED' in manifest,
         'manifest: BOOT_COMPLETED')
contract('CaptureBridge.attach' in kt_main, 'MainActivity: attach missing')
contract('androidx.work:work-runtime-ktx' in gradle,
         'gradle: work-runtime-ktx missing')
contract('assets/capture/' in pubspec, 'pubspec: capture assets missing')
contract("'androidx.work.ExistingWorkPolicy'" not in kt_health,
         'HealthPinger: sanity (KEEP policy expected)')
contract('ExistingWorkPolicy.KEEP' in kt_health, 'HealthPinger: KEEP policy')

allow_path = Path('assets/capture/allowlist.json')
contract(allow_path.exists(), 'assets/capture/allowlist.json missing')
if allow_path.exists():
    try:
        allow = json.loads(allow_path.read_text(encoding='utf-8'))
        contract(isinstance(allow, list) and len(allow) >= 20,
                 'allowlist.json: expected >= 20 packages')
        contract(all(isinstance(p, str) and '.' in p for p in allow),
                 'allowlist.json: non-package entries')
        for must in ('com.google.android.apps.nbu.paysa', 'com.phonepe.app',
                     'net.one97.paytm', 'com.cred.app', 'in.org.npci.bhim'):
            contract(must in allow, f'allowlist.json: {must} missing')
    except json.JSONDecodeError as e:
        errors.append(f'contract: allowlist.json invalid JSON: {e}')
contract('allowlist.json' in kt_listener, 'listener: allowlist.json ref')

# 6d. Kotlin symbol cross-references
contract('internal object CaptureLog' in kt_listener,
         'CaptureLog object missing')
for fn in ('fun bridge(', 'fun ioFailure('):
    contract(fn in kt_listener, f'CaptureLog.{fn} missing')
for ref in ('CaptureLog.bridge', 'CaptureLog.ioFailure'):
    users = [kt_health, kt_boot]
    contract(any(ref in u for u in users + [kt_listener, kt_bridge]),
             f'{ref} used nowhere')
for state in ('isListenerConnected', 'lastEventAt', 'engineRunning',
              'liveSink', 'installAllowlist'):
    contract(state in kt_listener, f'companion {state} missing in listener')
    contract(state in kt_bridge or state in kt_health,
             f'companion {state} not consumed by bridge/pinger')

# 6e. l10n parity (delegate getters AND parameterised methods vs
# both arbs — phase-04 introduced methods like importConfirmCta(n)).
l10n_getters = {
    m
    for m in (
        set(re.findall(r'String get (\w+)', dart_l10n))
        | set(re.findall(r'String (\w+)\(', dart_l10n))
    )
    if not m.startswith('_')
}
for arb in ('app_en.arb', 'app_hi.arb'):
    data = json.loads(
        Path(f'assets/l10n/{arb}').read_text(encoding='utf-8'))
    keys = {k for k in data if not k.startswith('@')}
    contract(keys == l10n_getters,
             f'{arb}: key set != delegate getters '
             f'(arb-only={sorted(keys - l10n_getters)}, '
             f'getter-only={sorted(l10n_getters - keys)})')

# 6f. routes + gate wiring
routes = Path('lib/core/constants/routes.dart').read_text(encoding='utf-8')
contract("captureGate = '/capture-gate'" in routes, 'routes: captureGate')
router = Path('lib/core/router/udao_router.dart').read_text(encoding='utf-8')
contract('Routes.captureGate' in router, 'router: gate route missing')
onboarding = Path('lib/features/onboarding/onboarding_screen.dart').read_text(
    encoding='utf-8')
contract('Routes.captureGate' in onboarding, 'onboarding: gate hook missing')

# 6g. parser package keys must be REAL android package ids.
# Phase-03 errata: the gpay parser shipped keyed on the corpus' fake
# id `com.google.android.apps.nobu` — a production GPay notification
# would never have matched (caught by the local 40-event e2e run).
gpay_parser = Path('lib/data/parsers/gpay_parser.dart').read_text(
    encoding='utf-8')
contract(
    "packageKey = 'com.google.android.apps.nbu.paysa'" in gpay_parser,
    'gpay parser must key on the real GPay package id')
for parser_file, real_id in (
    ('phonepe_parser.dart', 'com.phonepe.app'),
    ('paytm_parser.dart', 'net.one97.paytm'),
):
    src = (Path('lib/data/parsers') / parser_file).read_text(encoding='utf-8')
    contract(f"packageKey = '{real_id}'" in src,
             f'{parser_file}: real package id')
fake_pkg_assign = re.compile(
    r"packageKey\s*=\s*'com\.google\.android\.apps\.nobu'")
for f in list(Path('lib').rglob('*.dart')) + list(Path('test').rglob('*.dart')):
    src = f.read_text(encoding='utf-8')
    contract(fake_pkg_assign.search(src) is None,
             f'{f}: fake gpay package id assignment')
for f in Path('test/fixtures').glob('*.json'):
    src = f.read_text(encoding='utf-8')
    contract('com.google.android.apps.nobu' not in src,
             f'{f.name}: stale fake gpay package id')

# 6h. test determinism: the fake bridge's stream must deliver
# synchronously — async broadcast delivery races the frame in widget
# tests (phase-03 errata round 2).
fake_bridge_src = Path(
    'test/features/capture/fake_capture_bridge.dart'
).read_text(encoding='utf-8')
contract('broadcast(sync: true)' in fake_bridge_src,
         'fake bridge stream must deliver synchronously (sync: true)')

# 6i. Kotlin import sanity (phase-03 errata round 3: three files
# imported android.app.NotificationListenerService — the class lives
# in android.service.notification). Every import in the capture
# Kotlin files must be in the VERIFIED list below (each confirmed
# against the public Android / androidx / Flutter API surface).
VERIFIED_KOTLIN_IMPORTS = {
    'android.app.Notification',
    'android.app.ActivityManager',
    'android.app.ApplicationExitInfo',
    'android.app.NotificationChannel',
    'android.app.NotificationManager',
    'android.app.PendingIntent',
    'android.app.Service',
    'android.app.usage.UsageStatsManager',
    'android.content.BroadcastReceiver',
    'android.content.ComponentName',
    'android.content.Context',
    'android.content.Intent',
    'android.content.pm.PackageManager',
    'android.content.pm.ServiceInfo',
    'android.net.Uri',
    'android.os.Build',
    'android.os.Bundle',
    'android.os.Handler',
    'android.os.IBinder',
    'android.os.Looper',
    'android.os.PowerManager',
    'android.provider.Settings',
    'android.provider.Telephony',
    'android.service.notification.NotificationListenerService',
    'android.service.notification.StatusBarNotification',
    'androidx.core.app.NotificationCompat',
    'androidx.core.app.ServiceCompat',
    'androidx.core.content.ContextCompat',
    'androidx.work.BackoffPolicy',
    'androidx.work.ExistingPeriodicWorkPolicy',
    'androidx.work.ExistingWorkPolicy',
    'androidx.work.OneTimeWorkRequestBuilder',
    'androidx.work.PeriodicWorkRequestBuilder',
    'androidx.work.WorkManager',
    'androidx.work.Worker',
    'androidx.work.WorkerParameters',
    'io.flutter.embedding.engine.FlutterEngine',
    'io.flutter.plugin.common.EventChannel',
    'io.flutter.plugin.common.MethodChannel',
    'java.io.File',
    'java.util.concurrent.Executors',
    'java.util.concurrent.TimeUnit',
    'org.json.JSONObject',
    # phase-05: cross-package references inside the app.
    '`in`.udao.app.BuildConfig',
    # phase-06: AI bridge + ActivityManager RAM probe.
    '`in`.udao.app.ai.AiBridge',
    'android.app.ActivityManager',
    'android.content.Context',
    'android.graphics.Bitmap',
    'android.graphics.BitmapFactory',
    'android.os.Handler',
    'android.os.Looper',
    'com.google.mediapipe.framework.image.BitmapImageBuilder',
    'com.google.mediapipe.tasks.genai.llminference.GraphOptions',
    'com.google.mediapipe.tasks.genai.llminference.LlmInference',
    'com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession',
    'java.util.concurrent.atomic.AtomicInteger',
    '`in`.udao.app.capture.CaptureBridge',
    '`in`.udao.app.capture.HealthPinger',
    '`in`.udao.app.capture.UdaoNotificationListener',
    '`in`.udao.app.survival.NotificationGateway',
    '`in`.udao.app.survival.SurvivalBridge',
    'io.flutter.embedding.android.FlutterActivity',
}
# MainActivity.kt sits outside both globs but gained phase-05 imports;
# verify it too (it is the registration point for everything).
_MAINACTIVITY = Path('android/app/src/main/kotlin/in/udao/app/MainActivity.kt')
for f in capture_kt + power_kt + survival_kt + [_MAINACTIVITY]:
    for ln, line in enumerate(
            f.read_text(encoding='utf-8').splitlines(), 1):
        if line.startswith('import '):
            imported = line[len('import '):].strip()
            contract(imported in VERIFIED_KOTLIN_IMPORTS,
                     f'{f}:{ln}: unverified import {imported!r}')
contract('import android.app.NotificationListenerService' not in
         ''.join(f.read_text(encoding='utf-8') for f in capture_kt),
         'NotificationListenerService imported from the WRONG package '
         '(android.app.*) — it lives in android.service.notification')

# 6j. group-summary check must use the PUBLIC flag, not the hidden
# isGroupSummary() accessor (phase-03 errata round 3).
contract('.isGroupSummary' not in kt_listener,
         'listener uses the hidden isGroupSummary accessor — use the '
         'public Notification.FLAG_GROUP_SUMMARY bit instead')
contract('FLAG_GROUP_SUMMARY' in kt_listener,
         'listener must skip group summaries via FLAG_GROUP_SUMMARY')

# 6k. no forward-referenced property initialisers in the companion
# (DEFAULT_ALLOWLIST must be declared before its consumers).
allowlist_decl = kt_listener.find('private val DEFAULT_ALLOWLIST')
allowlist_use = kt_listener.find('= DEFAULT_ALLOWLIST')
contract(0 <= allowlist_decl < allowlist_use,
         'DEFAULT_ALLOWLIST must be declared before first use '
         '(Kotlin initialisers cannot forward reference)')

# ---- 6l. phase-04 capture-II contract ---------------------------------
# (a) PLAY FLAVOR SMS PURITY: no receiver, no SMS permissions, no
#     Telephony imports anywhere the play build compiles.
play_manifest = Path(
    'android/app/src/play/AndroidManifest.xml').read_text(encoding='utf-8')
for banned in ('RECEIVE_SMS', 'READ_SMS', 'UdaoSmsReceiver',
               'SMS_RECEIVED'):
    contract(banned not in play_manifest,
             f'play manifest must not contain {banned} (Play policy)')
play_kt_dir = Path('android/app/src/play/kotlin')
contract(not play_kt_dir.exists() or not any(play_kt_dir.rglob('*.kt')),
         'play source set must contain no Kotlin SMS code')
main_kt_all = '\n'.join(
    f.read_text(encoding='utf-8')
    for f in Path('android/app/src/main/kotlin').rglob('*.kt'))
contract(re.search(r'^import android\.provider\.Telephony', main_kt_all, re.M)
         is None,
         'main source set must not import Telephony '
         '(SMS glue is power-only; SmsGate stays pure)')

# (b) POWER receiver wiring.
power_manifest = Path(
    'android/app/src/power/AndroidManifest.xml').read_text(encoding='utf-8')
for needed in ('RECEIVE_SMS', 'READ_SMS', 'UdaoSmsReceiver',
               'android.provider.Telephony.SMS_RECEIVED'):
    contract(needed in power_manifest,
             f'power manifest missing {needed}')
sms_receiver = Path(
    'android/app/src/power/kotlin/in/udao/app/capture/UdaoSmsReceiver.kt')
contract(sms_receiver.exists(), 'UdaoSmsReceiver.kt missing in power set')
if sms_receiver.exists():
    rx_src = sms_receiver.read_text(encoding='utf-8')
    contract('Telephony.Sms.Intents.getMessagesFromIntent' in rx_src,
             'receiver must extract via Telephony.Sms.Intents')
    contract('WalWriter.append' in rx_src,
             'receiver must write to the SAME WAL')
    contract(rx_src.startswith('// phase-04'),
             'UdaoSmsReceiver.kt: missing // phase-04 header')

# (c) the pure gate lives in MAIN (unit-tested for every variant)
#     and encodes the WAL contract `sms:<sender>` + null title.
sms_gate = KDIR / 'SmsGate.kt'
contract(sms_gate.exists(), 'SmsGate.kt missing in main capture dir')
if sms_gate.exists():
    gate_src = sms_gate.read_text(encoding='utf-8')
    contract('"sms:$flat"' in gate_src,
             'SmsGate.walLine must encode pkg as sms:<SENDER>')
    contract('JSONObject.NULL' in gate_src,
             'SmsGate.walLine must null the notification-only fields')
    contract(gate_src.startswith('// phase-04'),
             'SmsGate.kt: missing // phase-04 header')
    contract(
        re.search(r'^import android\.provider\.Telephony', gate_src, re.M)
        is None,
        'SmsGate must stay pure (no Telephony import)')

# (d) Dart side of the SMS contract.
raw_event = Path(
    'lib/features/capture/bridge/capture_raw_event.dart'
).read_text(encoding='utf-8')
contract("pkg.startsWith('sms:')" in raw_event,
         'CaptureRawEvent.sender must decode the sms: prefix')
pipeline_src = Path(
    'lib/features/capture/pipeline/capture_pipeline.dart'
).read_text(encoding='utf-8')
contract('sender: raw.sender' in pipeline_src,
         'CapturePipeline must pass sender into ParserInput')
contract('packageKey: isSms ? null : raw.pkg' in pipeline_src,
         'CapturePipeline must null packageKey for SMS '
         '(TxnSource.sms labelling depends on it)')

# (e) new routes wired.
routes_src = Path('lib/core/constants/routes.dart').read_text(encoding='utf-8')
router_src = Path('lib/core/router/udao_router.dart').read_text(
    encoding='utf-8')
for r, const in (('/sms-gate', 'smsGate'),
                 ('/import-statement', 'importStatement'),
                 ('/gap', 'gap')):
    contract(f"{const} = '{r}'" in routes_src, f'routes: {const} missing')
    contract(f'Routes.{const}' in router_src, f'router: {const} unwired')

# (f) phase-04 deps pinned in pubspec. pdfrx/speech_to_text are EXACT
# pins: the caret ranges in the phase sketch did not exist on pub
# (^6.7.0) or diverged from the locally verified resolution (pdfrx
# 2.4.7 is what analyze+test ran against on the Windows box).
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')
for dep, pin in (('permission_handler', '11.3.1'),
                 ('pdfrx', '2.4.7'),
                 ('file_picker', '8.0.3'),
                 ('image_picker', '1.1.2'),
                 ('google_mlkit_text_recognition', '0.13.0'),
                 ('speech_to_text', '7.4.0'),
                 ('pointycastle', '3.9.1')):
    expected = f'{dep}: {pin}' if dep in ('pdfrx', 'speech_to_text') \
        else f'{dep}: ^{pin}'
    contract(expected in pubspec, f'pubspec: {expected} missing')

# (g) gradle JVM test wiring + the Kotlin test file.
gradle_src = Path('android/app/build.gradle.kts').read_text(encoding='utf-8')
contract('testImplementation("junit:junit:4.13.2")' in gradle_src,
         'gradle: junit testImplementation missing')
contract('testImplementation("org.json:json:' in gradle_src,
         'gradle: real org.json on the unit-test classpath missing')
sms_test = Path(
    'android/app/src/test/kotlin/in/udao/app/capture/SmsGateTest.kt')
contract(sms_test.exists(), 'SmsGateTest.kt missing')
if sms_test.exists():
    contract(sms_test.read_text(encoding='utf-8').startswith('// phase-04'),
             'SmsGateTest.kt: missing // phase-04 header')

# (h) receipt vault must seal, and the model leg must be honestly
#     absent (Err(ModelFailure('model-absent'))) until Phase 06.
ensemble = Path(
    'lib/features/capture/receipt/receipt_parser.dart'
).read_text(encoding='utf-8')
contract("ModelFailure('model-absent')" in ensemble,
         'ensemble model leg must return model-absent until Phase 06')
vault = Path(
    'lib/features/capture/receipt/receipt_vault.dart'
).read_text(encoding='utf-8')
contract('AesGcmCodec.encrypt' in vault,
         'receipt vault must seal thumbnails with AES-GCM')

# (i) no spinner widgets in the new flows (no CircularProgressIndicator,
#     no SpinBox) — skeletons only.
for f in Path('lib/features/capture').rglob('*.dart'):
    src = f.read_text(encoding='utf-8')
    contract('CircularProgressIndicator' not in src,
             f'{f}: spinners are banned (skeleton UI only)')

# (j) phase-04 headers on the new capture-II Dart files.
phase04_dart_dirs = (
    'lib/features/capture/ports',
    'lib/features/capture/import',
    'lib/features/capture/receipt',
    'lib/features/capture/quick',
    'lib/features/capture/gap',
    'lib/features/capture/permission/sms_gate_screen.dart',
)
for entry in phase04_dart_dirs:
    p = Path(entry)
    targets = [p] if p.is_file() else sorted(p.rglob('*.dart'))
    for f in targets:
        head = f.read_text(encoding='utf-8')[:200]
        contract(
            head.startswith('// phase-04') or head.startswith('// phase-06'),
            f'{f}: missing // phase-04 header')


# ---- 6m. analyzer shadow: const-RegExp, Set/Map method mixups,
#          missing project imports (the classes of bugs the phase-04
#          errata taught us static checks MUST catch) ----
# (a) RegExp has no const constructor — a `static const` (or const
#     list/map literal) carrying RegExp( is a compile error.
for f in Path('lib').rglob('*.dart'):
    text = f.read_text(encoding='utf-8')
    for m in re.finditer(r'static const [^=]+=[^;]*;', text, re.S):
        block = m.group(0)
        if 'RegExp(' in block:
            errors.append(f'{f}: const declaration holds RegExp (not const-able)')
    # crude: const <...>[ ... RegExp( ... ] up to the closing bracket
    for m in re.finditer(r'const <[^>]+>\[', text):
        # single-line literal (`]` before the next newline) — skip.
        nl = text.find('\n', m.end())
        if nl != -1 and text.find(']', m.end(), nl) != -1:
            continue
        chunk = text[m.end():m.end() + 4000]
        end = chunk.find('];')
        if end != -1 and 'RegExp(' in chunk[:end]:
            line = text[:m.start()].count('\n') + 1
            errors.append(f'{f}:{line}: const list literal holds RegExp')

# (b) Set used with Map-only methods (containsKey / operator [])
for f in list(Path('lib').rglob('*.dart')) + list(Path('test').rglob('*.dart')):
    text = f.read_text(encoding='utf-8')
    declared_sets = set(re.findall(
        r'(?:static )?const Set<[^>]+>\s+(\w+)', text))
    declared_sets |= set(re.findall(
        r'(?:static )?final Set<[^>]+>\s+(\w+)', text))
    for name in declared_sets:
        if re.search(r'\b' + name + r'\.containsKey\(', text):
            errors.append(f'{f}: Set {name} used with .containsKey()')

# (c) project-symbol import audit lives in tools/analyzer_shadow.py;
#     run it and fold failures in here.
import subprocess
shadow = subprocess.run(
    [sys.executable, 'tools/analyzer_shadow.py'],
    capture_output=True, text=True, cwd=Path('.').resolve(),
)
for line in shadow.stdout.splitlines():
    if line.startswith('FAIL'):
        errors.append('analyzer-shadow: ' + line)

# ---- 6n. phase-05 survival contract ------------------------------------
sb = Path('android/app/src/main/kotlin/in/udao/app/survival/SurvivalBridge.kt').read_text(encoding='utf-8')
ka = Path('android/app/src/main/kotlin/in/udao/app/survival/KeepAliveService.kt').read_text(encoding='utf-8')
ng = Path('android/app/src/main/kotlin/in/udao/app/survival/NotificationGateway.kt').read_text(encoding='utf-8')
hp = Path('android/app/src/main/kotlin/in/udao/app/capture/HealthPinger.kt').read_text(encoding='utf-8')
ww = Path('android/app/src/main/kotlin/in/udao/app/capture/WalWriter.kt').read_text(encoding='utf-8')
ma = Path('android/app/src/main/kotlin/in/udao/app/MainActivity.kt').read_text(encoding='utf-8')
mm = Path('android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
pw = Path('android/app/src/power/AndroidManifest.xml').read_text(encoding='utf-8')
pl = Path('android/app/src/play/AndroidManifest.xml').read_text(encoding='utf-8')
pb = Path('lib/features/survival/health/probe_bridge.dart').read_text(encoding='utf-8')
sp = Path('lib/features/survival/survival_providers.dart').read_text(encoding='utf-8')
bj = Path('lib/features/survival/jobs/background_jobs.dart').read_text(encoding='utf-8')
mn = Path('lib/main.dart').read_text(encoding='utf-8')
pp = Path('pubspec.yaml').read_text(encoding='utf-8')
l10 = Path('lib/l10n/app_localizations.dart').read_text(encoding='utf-8')

contract('udao/survival' in sb and "MethodChannel('udao/survival')" in pb,
        'survival channel name parity (Kotlin/Dart)')
for _m in ['getPowerState', 'getExitInfos', 'getWatchdogSnapshot',
           'getKeepAliveState', 'startKeepAlive', 'stopKeepAlive',
           'postNotification', 'openBatteryOptimizationSettings',
           'requestIgnoreBatteryOptimizations', 'openAppDetails',
           'openOemScreen']:
    contract(f'"{_m}"' in sb, f'SurvivalBridge.kt handles {_m}')
    contract(f"'{_m}'" in pb, f'probe_bridge.dart calls {_m}')
contract('FOREGROUND_SERVICE_TYPE_SPECIAL_USE' in ka,
        'KeepAliveService uses specialUse FGS type')
contract('HEARTBEAT_MS = 15L * 60L * 1000L' in ka, 'keep-alive 15-min heartbeat')
_onTask = ka[ka.index('override fun onTaskRemoved'):]
contract('stopSelf' not in _onTask[:_onTask.index('}')],
        'onTaskRemoved must never stopSelf')
contract('Band karo' in ng, 'keep-alive notice has a STOP action')
contract('REPEAT_MINUTES = 30L' in hp, 'watchdog 30-min cadence')
contract('REBIND_LATCH_MS = 5_000L' in hp, 'watchdog 5s rebind latch')
contract('ESCALATION_COOLDOWN_MS = 24L * 60L * 60L * 1000L' in hp,
        'escalation 24h cooldown')
contract('WalWriter.sweep' in hp and 'fun sweep' in ww,
        'pinger performs the 7-day WAL sweep')
for _k in ['watchdog_lastPingAt', 'watchdog_lastAction',
           'watchdog_startedDown', 'watchdog_lastEscalatedAt',
           'watchdog_oemSuspect', 'watchdog_listenerOk']:
    contract(f'"{_k}"' in hp, f'HealthPinger writes pref {_k}')
for _k in ['lastPingAt', 'lastAction', 'startedDown', 'listenerOk',
           'lastEscalatedAt', 'oemSuspect']:
    contract(f'"{_k}"' in sb, f'SurvivalBridge mirrors key {_k}')
contract('ExistingPeriodicWorkPolicy.KEEP' in hp,
        'kotlin periodic watchdog uses KEEP')
contract('"model" to Build.MODEL' in ma and '"isEmulator" to isEmulator()' in ma,
        'device info exposes model/versionRelease/isEmulator')
contract('SurvivalBridge.attach' in ma, 'MainActivity registers survival bridge')
contract('in.udao.app.survival.KeepAliveService' in mm and
        'android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE' in mm,
        'manifest declares KeepAliveService with specialUse property')
contract('android.permission.FOREGROUND_SERVICE_SPECIAL_USE' in mm,
        'specialUse FGS permission declared')
_perm = 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
contract(_perm in pw, 'power flavor declares the battery dialog permission')
contract(_perm not in pl and _perm not in mm,
        'play flavor + main manifest stay battery-permission-free')
contract('BuildConfig.FLAVOR != "power"' in sb,
        'direct battery ask double-guarded by flavor')
contract('workmanager: 0.10.10' in pp, 'workmanager pinned exactly')
contract('initializeBackgroundJobs' in mn, 'main.dart arms the jobs')
for _needle in ['ExistingPeriodicWorkPolicy.keep', 'requiresBatteryNotLow: true',
                'BackoffPolicy.exponential', "@pragma('vm:entry-point')"]:
    contract(_needle in bj, f'background_jobs.dart has {_needle}')
_dash_src = Path(
    'lib/features/survival/health/health_dashboard_screen.dart'
).read_text(encoding='utf-8')
contract('Share.share(' in _dash_src and 'SharePlus.' not in _dash_src,
        'diagnostics export uses the share_plus 10.x API (Share.share)')
# l10n: every survival getter carries BOTH branches (en + Hinglish).
_surv_block = l10[l10.index('Survival / health dashboard'):]
for _m in re.finditer(r'survival[A-Z]\w*', _surv_block):
    pass  # names collected below
_surv_names = sorted(set(re.findall(r'String (?:get )?(survival\w+)\(', _surv_block)))
_dupes = [n for n in set(_surv_names) if _surv_names.count(n) > 1]
contract(not _dupes, f'duplicate l10n survival getters: {_dupes}')
_en = len(re.findall(r"_code == 'en'", _surv_block))
contract(_en >= len(_surv_names),
        f'l10n survival getters missing en/hi branches '
        f'({_en} branches for {len(_surv_names)} getters)')

# ---- 6o. phase-05 errata guards -----------------------------------------
# (a) Dart digit separators (1_000_000) need language version >= 3.6;
#     this package's SDK floor is lower, so they are compile ERRORS.
#     Checked on string-stripped source (the contract test asserts
#     Kotlin's `5_000L` as a STRING, which stays legal).
for f in list(Path('lib').rglob('*.dart')) + list(Path('test').rglob('*.dart')):
    stripped = strip_dart(f.read_text(encoding='utf-8'))
    if re.search(r'\d_\d', stripped):
        errors.append(f'{f}: digit separators need SDK language 3.6 '
                      f'(package floor is lower) — write plain literals')

# (b) share_plus 10.x API boundary: SharePlus.instance / ShareParams
#     arrived in 11.x; on the pinned 10.x they are undefined names.
for f in Path('lib').rglob('*.dart'):
    stripped = strip_dart(f.read_text(encoding='utf-8'))
    if 'SharePlus.' in stripped or 'ShareParams(' in stripped:
        errors.append(f'{f}: SharePlus.instance/ShareParams are share_plus '
                      f'11+ APIs; the pinned 10.x exposes Share.share()')

# ---- 6p. phase-06 AI contract --------------------------------------------
aib = Path('android/app/src/main/kotlin/in/udao/app/ai/AiBridge.kt').read_text(encoding='utf-8')
aich = Path('lib/features/ai/runtime/ai_engine.dart').read_text(encoding='utf-8')
ma6 = Path('android/app/src/main/kotlin/in/udao/app/MainActivity.kt').read_text(encoding='utf-8')
gr6 = Path('android/app/build.gradle.kts').read_text(encoding='utf-8')
rt6 = Path('lib/features/ai/roast/roast_templates.dart').read_text(encoding='utf-8')
al6 = Path('lib/features/ai/agent/agent_loop.dart').read_text(encoding='utf-8')
re6 = Path('lib/features/ai/roast/roast_engine.dart').read_text(encoding='utf-8')
cc6 = Path('lib/features/chat/chat_controller.dart').read_text(encoding='utf-8')
l106 = Path('lib/l10n/app_localizations.dart').read_text(encoding='utf-8')
gi6 = Path('.gitignore').read_text(encoding='utf-8')

contract('"udao/ai"' in aib and "'udao/ai'" in aich,
        'AI channel name parity (Kotlin/Dart)')
contract("'udao/ai/stream'" in aib and "'udao/ai/stream'" in aich,
        'AI stream channel parity')
for _m in ['loadModel', 'unload', 'isLoaded', 'createSession',
           'closeSession', 'generate', 'generateVision', 'cancelGenerate']:
    contract(f'"{_m}"' in aib, f'AiBridge.kt handles {_m}')
    contract(f"'{_m}'" in aich, f'ai_engine.dart calls {_m}')
contract('cancelGenerateResponseAsync()' in aib and 'session.cancel()' not in aib,
        'cancel uses the REAL tasks-genai stop handle')
contract('tasks-genai:0.10.35' in gr6,
        'mediapipe tasks-genai pinned exactly')
contract('"totalRamMb"' in ma6, 'MainActivity exposes totalRamMb (tiering)')
for _g in ['*.task', '*.litertlm', '*.gguf']:
    contract(_g in gi6, f'gitignore bans {_g}')
for _f in Path('.').rglob('*.task'):
    contract(False, f'model binary in repo: {_f}')
for _f in Path('lib').rglob('*.dart'):
    if 'package:flutter_gemma' in _f.read_text(encoding='utf-8'):
        errors.append(f'{_f}: flutter_gemma is discontinued + network-tainted (ADR-0007)')
contract(rt6.count('RoastTemplate(') == 60,
        f'roast template count must be 60 (got {rt6.count("RoastTemplate(")})')
contract('static const int maxIterations = ToolPrompt.maxToolRounds;' in al6
        and 'maxToolRounds = 5' in Path('lib/features/ai/agent/tool_prompt.dart').read_text(encoding='utf-8'),
        'agent loop hard cap of 5 iterations')
contract('_guardrail.filter' in cc6,
        'chat controller runs EVERY ai line through the guardrail')
contract('_guardrail.filter' in re6,
        'roast engine runs its output through the guardrail')
# privacy: agent-loop log messages carry metrics only, never content
_log_msgs = re.findall(r"_log\.(?:info|warn|error)\(\s*'([^']*)'", al6)
contract(len(_log_msgs) > 0, 'agent loop telemetry logging present')
for _msg in _log_msgs:
    contract(re.match(r'^(iter|tool|cancel|engine|variation|stress)\b', _msg) is not None,
            f'agent loop log must stay metric-only: "{_msg[:40]}"')
# l10n: phase-06 getters exist in both branches
_ai_block = l106[l106.index('phase-06: chat'):]
_ai_names = re.findall(r'String (?:get )?((?:chat|persona|aiSettings|settingsAi)\w+)', _ai_block)
contract(len(_ai_names) >= 60,
        f'phase-06 l10n getters missing (got {len(_ai_names)})')

# ---- 7. stats ----
tests = 0
for f in Path('test/data').rglob('*.dart'):
    tests += len(re.findall(r'^\s*(?:test|testWidgets)\(',
                            f.read_text(encoding='utf-8'), re.M))

# merchant_cleaner_test registers per-case tests inside two for-loops
# (25 alias + 12 noise/casing cases); those two `test(` statements each
# expand at runtime. Runner truth: 148 statements -> 183 runtime tests.
runtime_tests = tests - 2 + 25 + 12

capture_tests = 0
for f in list(Path('test/features/capture').rglob('*.dart')) + \
        [Path('test/app_smoke_test.dart')]:
    capture_tests += len(re.findall(r'^\s*(?:test|testWidgets)\(',
                                    f.read_text(encoding='utf-8'), re.M))

print(f'files checked: {len(files)} (+{len(capture_dart)} capture dart, '
      f'{len(capture_kt)} capture kotlin)')
print(f'regex literals compiled: {nregex}')
print(f'test statements in test/data: {tests}')
print(f'expected runtime tests (flutter test test/data): {runtime_tests}')
print(f'test statements in capture tests (incl. smoke): {capture_tests}')

survival_tests = 0
for f in Path('test/features/survival').rglob('*.dart'):
    survival_tests += len(re.findall(r'^\s*(?:test|testWidgets)\(',
                                     f.read_text(encoding='utf-8'), re.M))
print(f'test statements in survival tests: {survival_tests}')

ai_tests = 0
for f in Path('test/features/ai').rglob('*.dart'):
    ai_tests += len(re.findall(r'^\s*(?:test|testWidgets)\(',
                               f.read_text(encoding='utf-8'), re.M))
chat_tests = 0
for f in Path('test/features/chat').rglob('*.dart'):
    chat_tests += len(re.findall(r'^\s*(?:test|testWidgets)\(',
                                 f.read_text(encoding='utf-8'), re.M))
print(f'test statements in ai tests: {ai_tests} (+{chat_tests} chat)')
print(f'survival files: {len(survival_dart)} dart + {len(survival_kt)} kotlin')
print(f'ai files: {len(ai_dart)} dart + {len(ai_kt)} kotlin')

# Sealed-class guard: Failure is sealed — extending it outside its
# library is a COMPILE error the symbol-shadow cannot see (learned in
# phase-07 errata: 4 test files failed to load from one subclass).
for f in Path('lib').rglob('*.dart'):
    if f.name == 'failure.dart':
        continue
    for ln, line in enumerate(
        f.read_text(encoding='utf-8').splitlines(), start=1
    ):
        if re.search(r'\bextends\s+Failure\b', line):
            errors.append(
                f'{f}:{ln}: extends Failure is a sealed-class violation '
                '(use DatabaseFailure/ParseFailure/UnexpectedFailure)'
            )
# Result-API guard: `.value` does not exist on Result (valueOrNull
# does) — the phase-07 errata class of typo.
for f in Path('lib').rglob('*.dart'):
    for ln, line in enumerate(
        f.read_text(encoding='utf-8').splitlines(), start=1
    ):
        if re.search(r'\bResult<[^>]+>\s+\w+\s*=.*\.value\s*\?', line):
            errors.append(f'{f}:{ln}: Result has no .value — use valueOrNull')
if errors:
    print(f'ERRORS: {len(errors)}')
    for e in errors:
        print('  ' + e)
    sys.exit(1)
print('ALL STATIC CHECKS PASS')
