// phase-04
// POWER FLAVOR ONLY — never compiled into the play build (this file
// lives in the `power` source set; the receiver + its manifest entry
// + RECEIVE_SMS/READ_SMS permissions simply do not exist in play).
//
// The system-broadcast glue for SMS capture: Telephony extraction
// (multipart concatenation) -> SmsGate (pure, unit-tested) -> the
// SAME zero-loss WAL the notification listener writes to. WAL-only
// by design: the Flutter engine is usually dead when an SMS lands;
// the next app start replays the tail. OTPs from real banks pass
// this gate and die in the Dart pipeline's OtpFilter — never
// persisted, never logged.
package `in`.udao.app.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class UdaoSmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }
        val messages =
            Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val first = messages.firstOrNull() ?: return
        val sender = first.originatingAddress ?: return
        if (!SmsGate.isTransactionalSender(sender)) {
            return // promo noise dies natively
        }
        val body = messages.joinToString("") { it.displayMessageBody ?: "" }
        if (body.isBlank()) {
            return
        }
        // Same law as notifications: durable write FIRST, on the
        // broadcast thread — the replay owns the rest.
        try {
            WalWriter.append(
                context.applicationContext,
                SmsGate.walLine(sender, body, System.currentTimeMillis()),
            )
        } catch (e: Exception) {
            CaptureLog.ioFailure("sms.wal", e)
        }
    }
}
