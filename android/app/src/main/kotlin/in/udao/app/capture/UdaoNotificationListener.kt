// phase-03
// UDAO's primary capture surface — the NotificationListenerService.
//
// The SYSTEM binds this service, so events arrive even after the app
// process was killed (everything short of force-stop). The one job
// here is: allowlist check -> field extraction -> WAL append -> live
// push if the Flutter engine is listening. NOTHING ELSE. No parsing
// (that is Dart's single source of truth), no wake locks, no network.
//
// Rebind policy: onListenerDisconnected() NEVER calls requestRebind
// spuriously — the HealthPinger watchdog (cadence owned by Phase 05)
// and the BootReceiver own recovery.
package `in`.udao.app.capture

import android.app.Notification
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

class UdaoNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        Companion.isListenerConnected = true
        reloadAllowlist(applicationContext)
        CaptureLog.connected(true)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Companion.isListenerConnected = false
        CaptureLog.connected(false)
        // No requestRebind here, by design. See class kdoc.
    }

    override fun onListenerHintsChanged(hints: Int) {
        super.onListenerHintsChanged(hints)
        // Informational only (e.g. Android 15 marking the listener
        // "untrusted" for OTP content — we drop OTPs in Dart anyway).
        CaptureLog.hints(hints)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) {
            return
        }
        // 1. Group summaries re-package the children — skip or every
        //    group message would be counted twice. Public-API check
        //    only: the convenience accessor is hidden API, but the
        //    FLAG_GROUP_SUMMARY bit is public since API 20.
        val notification: Notification = sbn.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) {
            return
        }
        // 2. Allowlist first: non-allowlisted packages are never even
        //    written to the WAL (privacy + disk law).
        val pkg: String = sbn.packageName ?: return
        if (!allowlist().contains(pkg)) {
            return
        }
        // 3. Null-safe field extraction. getCharSequence, not
        //    getString — notification extras store CharSequences and
        //    malformed extras must never crash the service.
        val extras = notification.extras
        val title: String? = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text: String? = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText: String? = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val subText: String? = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()

        val line: String = try {
            JSONObject()
                .put("pkg", pkg)
                .put("title", title ?: "")
                .put("text", text ?: "")
                .put("bigText", bigText ?: "")
                .put("subText", subText ?: "")
                .put("ts", sbn.postTime)
                .toString()
        } catch (_: Exception) {
            return // JSONObject.put on primitives cannot throw, but the
                   // zero-loss law says the service must never die.
        }

        // 4. WAL FIRST — always, even when nobody is listening.
        try {
            WalWriter.append(applicationContext, line)
        } catch (e: Exception) {
            CaptureLog.ioFailure("wal.append", e)
            return // if the write failed, the event is lost either way;
                   // do NOT push a half-durable event downstream.
        }
        Companion.lastEventAt = sbn.postTime

        // 5. Then, only if the Flutter engine is live, mirror it to the
        //    open EventChannel sink (main thread — sinks are not
        //    thread-safe).
        if (Companion.engineRunning) {
            val sink = Companion.liveSink
            if (sink != null) {
                mainHandler.post {
                    try {
                        sink.success(line)
                    } catch (_: Exception) {
                        // Engine died between the flag check and the
                        // post — the WAL entry still holds the event.
                    }
                }
            }
        }
    }

    companion object {
        @Volatile
        var isListenerConnected: Boolean = false
            private set

        @Volatile
        var lastEventAt: Long = 0L
            private set

        /** Set by CaptureBridge when a Dart listener attaches. */
        @Volatile
        var engineRunning: Boolean = false

        /** The open EventChannel sink, if the engine is listening. */
        @Volatile
        var liveSink: io.flutter.plugin.common.EventChannel.EventSink? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * Fallback set — used until Dart pushes the asset allowlist.
         * The asset version (assets/capture/allowlist.json) is the
         * editable source of truth; this constant only needs to be
         * good enough for the very first boot.
         *
         * NOTE: declared BEFORE the property that initialises from it
         * — Kotlin property initialisers cannot forward reference
         * (phase-03 errata round 3).
         */
        // TODO-VERIFY(local): bank app package ids — confirm each on a
        // real device (adb shell pm list packages | grep -i <bank>)
        // before release; bank apps matter little until Phase 04 SMS
        // capture, notifications are dominated by the UPI apps above.
        private val DEFAULT_ALLOWLIST: Set<String> = setOf(
            // UPI / wallet apps (high-value, verified names)
            "com.google.android.apps.nbu.paysa", // Google Pay
            "com.phonepe.app",                   // PhonePe
            "net.one97.paytm",                   // Paytm
            "com.paytm.payer",                   // Paytm (payer variant)
            "com.cred.app",                      // CRED
            "in.org.npci.bhim",                  // BHIM
            "com.amazon.mShop.android.shopping", // Amazon Shopping
            // Top-15 Indian bank apps (TODO-VERIFY each id locally)
            "com.sbi.lotusintouch",              // SBI YONO
            "com.hdfcbank.mobilebanking",        // HDFC Bank
            "com.csam.icici.bank.imobile",       // ICICI iMobile
            "com.axis.mobile",                   // Axis Mobile
            "com.kotak.mb",                      // Kotak-811
            "com.Version1.PNBOne",               // PNB ONE
            "com.bankofbaroda.mpassbook",        // BoB M-Passbook
            "com.canarabank.mobility",           // Canara Mobile
            "com.unionbank.unionmobileapp",      // UnionBank
            "com.idfcfirstbank.aura",            // IDFC First
            "com.indusind.psbindusmobile",       // IndusInd
            "com.yesbank.yesmobile",             // Yes Bank
            "com.federalbank.fedbook",           // FedBook
            "com.airtelapp",                     // Airtel Thanks
            "com.myairtelapp.uat",               // Airtel (legacy id)
        )

        /**
         * Allowlist state. Bootstrapped from DEFAULT_ALLOWLIST, then
         * replaced by whatever Dart last pushed (assets/capture/
         * allowlist.json, cached in no_backup/allowlist.json so it
         * survives restarts without the engine running).
         */
        @Volatile
        private var allowlist: Set<String> = DEFAULT_ALLOWLIST

        fun allowlist(): Set<String> = allowlist

        fun reloadAllowlist(context: Context) {
            val file = java.io.File(context.noBackupFilesDir, "allowlist.json")
            if (!file.exists()) {
                return
            }
            try {
                val parsed = parseAllowlist(file.readText())
                if (parsed.isNotEmpty()) {
                    allowlist = parsed
                }
            } catch (e: Exception) {
                CaptureLog.ioFailure("allowlist.reload", e)
            }
        }

        fun installAllowlist(json: String): Boolean {
            val parsed = try {
                parseAllowlist(json)
            } catch (e: Exception) {
                CaptureLog.ioFailure("allowlist.parse", e)
                return false
            }
            if (parsed.isEmpty()) {
                return false
            }
            allowlist = parsed
            return true
        }

        private fun parseAllowlist(json: String): Set<String> {
            val arr = org.json.JSONArray(json)
            val out = HashSet<String>(arr.length())
            for (i in 0 until arr.length()) {
                val pkg = arr.optString(i)
                if (pkg.isNotBlank()) {
                    out.add(pkg)
                }
            }
            return out
        }

    }
}

/** Logging scope — pkg/ts/state only, NEVER notification text. */
internal object CaptureLog {
    private const val TAG = "UdaoCapture"

    fun connected(value: Boolean) {
        android.util.Log.i(TAG, "listener ${if (value) "connected" else "disconnected"}")
    }

    fun hints(hints: Int) {
        android.util.Log.d(TAG, "listener hints changed: $hints")
    }

    fun ioFailure(where: String, e: Exception) {
        android.util.Log.w(TAG, "$where failed: ${e.message}")
    }

    fun bridge(message: String) {
        android.util.Log.i(TAG, message)
    }
}
