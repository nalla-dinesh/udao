# OEM Survival Guide — UDAO on hostile Android skins

> The honest manual. Android makers (MIUI/HyperOS, One UI, ColorOS,
> Funtouch, EMUI, MagicOS, OxygenOS) all "optimize" background apps
> to death. This doc explains what UDAO does about it, what only YOU
> can do, and how to verify both on a real phone.

## 1. What actually kills us

| Killer | What it looks like | UDAO's defense |
|--------|-------------------|----------------|
| Listener unbind | system drops the NotificationListener binding (reboot, OTA, OEM cleaner) | watchdog rebind ladder (see §2) |
| Process kill | app process recycled; WAL catches events missed mid-flight | WAL-first design (phase-03) + rebind |
| Battery optimization / doze | defers everything in idle | exemption card + honest notes |
| Autostart off | after reboot we never come back | OEM guide (§4) + BootReceiver |
| Swipe-away cleaners (MIUI "Boost speed" etc.) | locked-app lists | keep-alive service (§3, optional) |

## 2. The watchdog (automatic, in every build)

A 30-minute Kotlin worker (`HealthPinger`) checks the listener and,
when it is down, walks a fixed ladder:

```
rebind → wait 5s → component toggle → wait 5s → escalate
                                              (max 1 notification / 24h)
```

- The escalation notification opens the app's health screen.
- Every run leaves a snapshot the health dashboard shows ("last run:
  rebind se theek hua").
- The same worker trims the WAL to 7 days and flags OEM suspects.
- **Battery cost: <1%/day** for this passive setup (listener +
  watchdog). That is the claim we stand behind; anything more is the
  optional service below.

## 3. Keep-alive service (optional, user-armed)

For phones where even the toggle workaround gets overridden. Armed
ONLY from the health dashboard:

- runs as a `specialUse` foreground service (Android 14+ subtype
  property declared),
- shows a MIN-priority permanent notice with a **Band karo** stop
  action,
- beats every 15 minutes: re-requests the binding if it dropped,
- survives swipe-away (`onTaskRemoved` is deliberately empty),
- never starts on its own — not from boot, not from a job.

Battery honesty: this one is NOT free — it holds a foreground
service. The card says so; it is the user's call.

## 4. The per-maker matrix (in-app: Health → setup guide)

The app detects the maker from `Build.MANUFACTURER` + `Build.BRAND`
(brand first: Poco/Redmi → Xiaomi, iQOO stays its own guide) and
renders typed steps with deep-link buttons. Deep links are
undocumented OEM territory — every guide also carries the manual
path, and dontkillmyapp.com is linked as the community reference.

| Maker | The two things that matter |
|-------|---------------------------|
| Xiaomi / Poco / Redmi | Autostart ON + Battery saver "No restrictions" (+ lock in recents) |
| Samsung | Never sleeping apps + battery Unrestricted |
| Oppo / Realme | Startup manager allow + background battery allow |
| Vivo / iQOO | Background power whitelist + autostart |
| Huawei / Honor | App launch → Manage manually (all three) + protected apps |
| OnePlus | Auto-launch allow + battery exempt |
| Nokia / stock | battery exempt, that's it |

Version warning: OEMs rename these screens between OS majors (MIUI →
HyperOS, ColorOS 13). The in-app copy never promises a permanent
path; manual steps are always shown.

## 5. Battery optimization — the two builds

- **Play build** (Google Play): opens the system's battery list —
  find UDAO, set Unrestricted. One extra tap, zero policy risk.
- **Power build** (sideload): asks the direct system dialog first,
  falls back to the list, then app details.

## 6. Weekly gap check

Sundays ~20:00 IST a background job re-runs the gap detector (same
logic as the Gap screen). If the week looks broken, the finding is
parked in the kv store and surfaces as a notification + card the
next time you open the app. (The background isolate cannot reach the
notification channel — ADR-0006; latency is the honest price.)

## 7. Nightly hygiene

Between 01:00–04:00 IST (best-effort; WorkManager is inexact by
design and battery-not-low is required):

- raw notification/SMS text older than 24 h is blanked in the DB
  (rows keep hash + parsed fields),
- the capture WAL is trimmed to 7 days,
- a rollup counter is written for the health dashboard.

## 8. Verifying on a real phone (adb protocol)

Run `tools/oem_test.sh` (bash + adb) — it prints:

1. notification-listener binding state
   (`dumpsys notification | grep -i listener`),
2. battery-optimization exemption
   (`dumpsys deviceidle | grep -i udao`),
3. app standby bucket + background restriction
   (`dumpsys usagestats`, `dumpsys activity`),
4. the last process exit reasons (API 30+; same source as the
   dashboard's "pehle app kyu band hua" card),
5. WorkManager job state
   (`dumpsys jobscheduler | grep -i udao`),
6. the keep-alive service state, when armed.

Manual OEM drill (the protocol the script cannot do for you):

1. reboot the phone → open the health screen within 2 minutes →
   stamp should return to SHARP (watchdog rebind),
2. swipe the app away → post a ₹1 UPI test txn → it should still
   land (WAL + service),
3. toggle a battery saver / cleaner → confirm the escalation
   notification arrives at most once per 24 h,
4. follow the in-app OEM guide → re-check the device-truth card.

## 9. What we refuse to do

- no `dataSync`/`mediaPlayback` FGS types (Android 15 timeouts +
  Play scrutiny),
- no foreground service from boot (Android 15 ban),
- no wake locks, no `setExact` alarms,
- no reflection into OEM power managers,
- no fake "all good" states — if something cannot be read, the UI
  says "pata nahi".
