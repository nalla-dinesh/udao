# SMS Declaration Pack — UDAO (for the human to submit)

**Status: DRAFT, prepared Phase 04. Current Play build ships NO SMS
code at all** (see `android/app/src/play/` — no receiver, no
`RECEIVE_SMS`/`READ_SMS`, verified by `tools/static_verify.py` §6l).
This pack exists so that IF you decide to bring bank-SMS capture to
the Play listing via the "SMS-based money management" exception, you
can do it without writing policy prose from scratch.

Everything below is written to be pasted into the Play Console's
permission declaration form and supporting materials.

---

## 1. Why the power build exists at all

Google Play's SMS policy restricts `RECEIVE_SMS`/`READ_SMS` to a
narrow exception set. UDAO's core capture runs on **notification
access** (no SMS permission) and that is what the Play build ships.
The **power flavor** (GitHub/F-Droid sideload) adds bank-SMS capture
for payments that never post a notification. This file is the path
to merging that capability into the Play listing legally.

## 2. The exception UDAO qualifies under

**"SMS-based money management"** — core, user-visible functionality
that requires SMS access to work.

Claim text (paste into the declaration form):

> UDAO is an offline personal-finance ledger for Indian users. Its
> core functionality is automatic expense tracking: the app reads
> transactional bank SMS (debit/credit confirmations from verified
> bank sender IDs, e.g. VM-HDFCBK) and converts them into ledger
> entries on the device. This is the app's primary and most
> prominent feature — the home screen is the ledger these SMS build.
> No SMS is sent, deleted, or modified; the app only reads incoming
> transactional SMS. All processing is on-device; there is no
> account creation, no server, and the app holds no INTERNET
> permission, so message contents cannot leave the device. OTP
> messages are detected and discarded before storage; promotional
> messages are discarded at the native gate before any storage or
> logging. Raw SMS text is retained in an encrypted on-device file
> for at most 24 hours and then destroyed; only the parsed
> transaction (amount, merchant, reference, timestamp) is retained,
> in an SQLCipher-encrypted database whose key lives in the Android
> Keystore. The SMS permission is requested at runtime, only after
> an in-app screen that states exactly what is read, what is
> discarded, and for how long anything is retained.

## 3. Permission declaration form — answer drafts

| Form field | Draft answer |
| --- | --- |
| Which permission(s)? | `RECEIVE_SMS` (and `READ_SMS` only if the console form demands it for the same receiver; reading is via the SMS_RECEIVED broadcast, so `RECEIVE_SMS` is the operative permission) |
| Core feature affected | Automatic expense ledger from bank transactional SMS (money management). |
| Is this feature the app's primary purpose? | Yes — capture-and-ledger is the product; SMS is one of its two capture inputs (notifications, SMS). |
| Do you send, write, or delete SMS? | No. Read-only, incoming only. |
| Do you upload message contents anywhere? | No. The app has no INTERNET permission and no analytics SDKs; exfiltration is technically impossible. |
| Retention | Raw text ≤ 24 h in an encrypted file, then deleted. Parsed transactions persist in an encrypted DB until the user deletes them. |
| OTP handling | OTP messages are identified and discarded pre-storage (never persisted, never logged). |
| User consent flow | Dedicated in-app screen (power build → Settings → SMS capture): what is read, what is dropped, retention, offline promise; then the Android runtime dialog. Declined = feature stays off; app remains fully usable via notification capture. |
| Alternative for users who decline | Notification-based capture (no SMS permission) + manual entry + bank-statement PDF import. |

## 4. Demo video script (record with AIRPLANE MODE ON)

The airplane-mode recording is the whole proof: capture works with
radios off, so nothing can be leaving the device.

1. **(0:00–0:10)** Phone settings: Airplane mode ON. Show it.
2. **(0:10–0:25)** Install/open the power build. Home screen (empty
   ledger). Settings → SMS capture → the honest-facts screen. Point
   at the OTP-dropped and 24-hour-retention bullets.
3. **(0:25–0:40)** Grant SMS permission via the runtime dialog.
4. **(0:40–1:10)** Use another device (or adb, off-camera) to push a
   realistic transactional SMS to the phone — e.g.
   `VM-HDFCBK: Rs.148.00 debited from A/c XX1234 on 28-10-26 REF
   512345678901 UPI/SWIGGY.` The SMS lands.
5. **(1:10–1:30)** Open UDAO: the ₹148 Swiggy entry is in the
   ledger with amount, merchant, category. Tap the entry: shows
   parsed fields, source "sms".
6. **(1:30–1:50)** Push an OTP SMS (`Your OTP is 482913`) and a
   promo SMS. Show UDAO: neither appears anywhere; the ledger is
   unchanged. (This is the money shot for the reviewer.)
7. **(1:50–2:00)** Airplane mode still ON. End.

Keep it under 2 minutes; narrate in English; screen-record at 1080p.

## 5. Listing-copy requirements

- Feature must be **prominently documented in the listing**: a
  screenshot/bullet on the main description, not buried in an
  expandable.
- Draft description bullet: *"Reads your bank's transactional SMS to
  build your ledger automatically — fully offline. OTPs and promos
  are ignored. Nothing ever leaves your phone (the app has no
  internet access at all)."*
- Add a privacy-policy URL covering: SMS read scope, on-device
  processing, ≤24 h raw retention, encrypted storage, no network.
- The data-safety form must declare: SMS messages — collected? No
  (not transmitted anywhere; device-only processing must still be
  disclosed as "processed ephemerally" per the form's wording).

## 6. Closed-test plan (12 testers, 14 days)

- [ ] Create a closed test track; add 12 testers (mix of Android
      11/12/13/14/15, at least 2 with dual-SIM).
- [ ] Upload the build that carries the SMS receiver (power parity,
      `--flavor power` release).
- [ ] Submit the permission declaration BEFORE inviting testers
      (Play blocks SMS-permission apps in testing until approved).
- [ ] Record the airplane-mode demo video (§4) and attach it to the
      declaration.
- [ ] Day-by-day: D1 invite, D1–D7 capture + retry flow (grant,
      deny, permanently-deny paths), D8–D14 gap/dedup validation
      (notification + SMS for the same payment must not
      double-count; corpus covers this in tests, field-verify).
- [ ] Collect: any real bank SMS format that failed to parse
      (forward the SMS text — UDAO's in-app diagnostics never log
      raw SMS, so ask testers to paste the text manually).
- [ ] After 14 days: if all 12 testers active and no crashes in the
      SMS path, promote to production; else iterate.

## 7. What this pack does NOT cover

- The play build's notification-only capture needs no declaration —
  nothing in this file applies to it.
- The "Power+" accessibility-service experiment is explicitly out of
  scope (not built, per the phase-04 DO-NOT list; any future attempt
  would need its own declaration pack).
