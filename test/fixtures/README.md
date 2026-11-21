# Parser golden corpus

Two JSON files, 250 samples total, the phase-02 parser acceptance
evidence (`test/data/parsers/golden/parser_golden_test.dart`).

- `corpus_notifications.json` — 65 notification captures (GPay /
  PhonePe / Paytm package keys + body-probe-only cases).
- `corpus_sms.json` — 185 SMS captures (7 banks x 5 template families
  x 4 merchants = 140 template variants, plus adversarial cases).

Each sample:

```json
{
  "id": "hdfc_0007",
  "kind": "sms",
  "packageKey": null,          // or com.google.android.apps.nobu, …
  "sender": "VM-HDFCBK",       // SMS address, null for notifications
  "text": "Rs.148.50 debited from …",
  "expect": {
    "class": "auto",            // auto | pending | drop
    "parserId": "hdfc",
    "amountPaise": 14850,
    "direction": "debit",
    "merchantClean": "Swiggy",
    "confidenceMin": 0.85,
    "occurredAtIsoDate": "2026-10-27",
    "hasVpa": false,            // optional
    "hasRef": true,             // optional
    "dropReason": null          // drops only
  }
}
```

`receivedAtIso` (top level) pins the receive clock for every sample,
so timestamps and 10-minute dedup buckets are deterministic.

**185 machine-generated template variants** come from
`tools/gen_corpus.py` — which also models the Dart parser chain 1:1
(same regexes, same registry order) and cross-checks 65
**hand-authored adversarial** samples against independent
expectations before emitting anything. Regenerate:

```bash
python3 tools/gen_corpus.py
```

Class mix: 215 auto / 17 pending / 18 drop. Field accuracy gate:
>= 95% per asserted field.
