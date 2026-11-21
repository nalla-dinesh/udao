// phase-04
// Pure SMS admission logic — NO Android SMS framework imports, so it
// lives in the MAIN source set and unit-tests run for every variant.
// Everything SMS-Android (receiver, Telephony API, manifest, runtime
// permission) stays in the POWER flavor only; this object is inert
// text processing that nothing in the play build can reach.
//
// Two jobs:
//   1. sender gate — transactional senders only, promos die natively
//      (their bodies are never written to the WAL, never logged);
//      OTPs from real banks still pass the gate and are dropped by
//      the DART pipeline's OtpFilter (never persisted either).
//   2. WAL line shape — identical to notification lines so the whole
//      replay/pipeline path is unchanged:
//      {"pkg":"sms:<sender>","title":null,"text":body,"ts":...}
package `in`.udao.app.capture

import org.json.JSONObject

object SmsGate {

    // TRAI transactional routes: "VM-HDFCBK", "JD-PAYTM", "BX-ICICIB"
    // (2-letter operator + 4-8 alphanumeric), or a plain 6-10 letter
    // institutional id ("HDFCBK", "PAYTM"). Everything else — numeric
    // promo senders ("992030"), phone numbers, emails, short junk —
    // dies here. Documented deliberately WIDER than the phase sketch
    // ([A-Z0-9]{4,6}) because real bank tags run to 7 chars
    // ("VM-BARDBKB" = Bank of Baroda).
    // Optional trailing "-S"-style route suffix: real devices report
    // senders like "JD-BOBSMS-S" / "JX-BOBSMS-S" (Bank of Baroda via
    // live capture, 2026-11-04) — one extra dash+token after the
    // institutional id. Still rejects numeric promo senders, phone
    // numbers and emails.
    private val TRANSACTIONAL_SENDER =
        Regex("^(?:[A-Z]{2}-[A-Z0-9]{4,8}(?:-[A-Z0-9]{1,4})?|[A-Z]{6,10})$")

    /** True when the sender address looks transactional. */
    fun isTransactionalSender(sender: String?): Boolean {
        if (sender == null) {
            return false
        }
        val flat = sender.trim().uppercase()
        return TRANSACTIONAL_SENDER.matches(flat)
    }

    /**
     * Builds the WAL line for one (multipart-concatenated) SMS.
     * The Dart pipeline maps `pkg` "sms:<SENDER>" back onto
     * ParserInput.sender for the bank parsers.
     */
    fun walLine(sender: String, body: String, ts: Long): String {
        val flat = sender.trim().uppercase()
        return JSONObject()
            .put("pkg", "sms:$flat")
            .put("title", JSONObject.NULL)
            .put("text", body)
            .put("bigText", JSONObject.NULL)
            .put("subText", JSONObject.NULL)
            .put("ts", ts)
            .toString()
    }
}
