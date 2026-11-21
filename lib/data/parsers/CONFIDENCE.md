# Parser confidence policy

Every parser emits a `confidence` in `[0.0, 1.0]`. The `LedgerRepo`
ingest pipeline routes on two thresholds defined in
`parser_types.dart` (`ConfidencePolicy`):

| Band | Range | Outcome |
| --- | --- | --- |
| Auto-accept | `>= 0.8` | Straight into `txn` (dedup-keyed) |
| Review | `0.6 <= c < 0.8` | Parked in `pending_review` |
| Drop | `< 0.6` | `capture_event` row + `ParseFailure('low_confidence')` |

## Scores by parser

| Parser | Score | Rationale |
| --- | --- | --- |
| `gpay` full | 0.95 | App-native notification, first-party text |
| `phonepe` full | 0.95 | App-native notification |
| `paytm` full | 0.90 | App-native, wallet/mixed wording variants |
| banks (`hdfc`…`bob`) full | 0.85 | Sender-tagged, explicit debit/credit + ref |
| any parser partial | 0.70 | Amount found, merchant phrasing unknown |
| `generic_upi` | 0.65 | Regex-net over unknown UPI text |

## Rules of thumb

1. **A missing merchant never blocks capture** — it lowers the score
   to the review band, a human fills the blank.
2. **App notifications outrank bank SMS** for the same payment: the
   repo writes whichever arrives first; the other is suppressed by
   dedup fingerprint (`DedupEngine`) or the `findNear` 10-minute
   window.
3. **No parser writes below 0.6 silently.** Drops are recorded with
   stable codes (`otp_security`, `promo_marketing`, `no_parser_match`,
   `low_confidence`) for the capture health dashboard.
