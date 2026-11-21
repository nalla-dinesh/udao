// phase-05 (extends phase-03)
// Listener health watchdog — the ONLY owner of rebind cadence.
//
// Recovery ladder (spec of record; mirrored by the pure-Dart
// WatchdogPlanner on the health dashboard — keep both in sync):
//   1. rebind     — static requestRebind (safe in every state)
//   2. wait       — REBIND_LATCH_MS grace: binding callbacks are async
//   3. toggle     — disable+re-enable the component (stuck MIUI/vivo
//                   binding workaround, mirrors CaptureBridge)
//   4. wait       — same grace again
//   5. escalate   — ONE high-priority notification per 24h max
//                   (cooldown persisted in the survival prefs)
// Every run then: snapshot to prefs (Dart syncs it on app open) + the
// 7-day WAL sweep + an OEM-suspect flag for the dashboard.
package `in`.udao.app.capture

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import androidx.work.BackoffPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import `in`.udao.app.survival.NotificationGateway
import java.util.concurrent.TimeUnit

/** Action taken by the last watchdog run (slug is the Dart contract). */
enum class WatchdogAction(val slug: String) {
    NONE("none"),
    REBIND("rebind"),
    TOGGLE("toggle"),
    ESCALATED("escalated"),
    SUPPRESSED("suppressed"),
}

class HealthPinger(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    override fun doWork(): Result {
        return try {
            val ctx = applicationContext
            val startedDown = !UdaoNotificationListener.isListenerConnected
            var action = WatchdogAction.NONE
            if (startedDown) {
                rebind()
                action = WatchdogAction.REBIND
                Thread.sleep(REBIND_LATCH_MS)
                if (!UdaoNotificationListener.isListenerConnected) {
                    toggleRebind()
                    action = WatchdogAction.TOGGLE
                    Thread.sleep(REBIND_LATCH_MS)
                    if (!UdaoNotificationListener.isListenerConnected) {
                        action =
                            if (maybeEscalate(ctx)) {
                                WatchdogAction.ESCALATED
                            } else {
                                WatchdogAction.SUPPRESSED
                            }
                    }
                }
            }
            writeSnapshot(ctx, startedDown, action)
            runCatching { WalWriter.sweep(ctx) }
                .onFailure {
                    CaptureLog.ioFailure("wal.sweep", IllegalStateException(it))
                }
            Result.success()
        } catch (e: Exception) {
            CaptureLog.ioFailure("health.pinger", e)
            // A failed ping is not fatal — backoff retries (exponential,
            // set at enqueue time for the periodic chain).
            Result.retry()
        }
    }

    private fun rebind() {
        val component = ComponentName(applicationContext, UdaoNotificationListener::class.java)
        NotificationListenerService.requestRebind(component)
        CaptureLog.bridge("pinger: requestRebind issued")
    }

    /** Same primitives as CaptureBridge.rebindViaToggle, callable without an engine. */
    private fun toggleRebind() {
        val pm = applicationContext.packageManager
        val component = ComponentName(applicationContext, UdaoNotificationListener::class.java)
        pm.setComponentEnabledSetting(
            component,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            component,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        NotificationListenerService.requestRebind(component)
        CaptureLog.bridge("pinger: component toggle issued")
    }

    /** At most one escalation notification per [ESCALATION_COOLDOWN_MS]. */
    private fun maybeEscalate(ctx: Context): Boolean {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val last = prefs.getLong(KEY_LAST_ESCALATED_AT, 0L)
        val now = System.currentTimeMillis()
        if (now - last < ESCALATION_COOLDOWN_MS) {
            CaptureLog.bridge("pinger: escalation suppressed (cooldown)")
            return false
        }
        NotificationGateway.postHealth(
            ctx,
            NotificationGateway.ID_ESCALATION,
            "UDAO capture ruk gaya",
            "Notification access wapas jodna hoga. Ek tap mein settings kholo.",
        )
        prefs.edit().putLong(KEY_LAST_ESCALATED_AT, now).apply()
        CaptureLog.bridge("pinger: escalation notification posted")
        return true
    }

    private fun writeSnapshot(
        ctx: Context,
        startedDown: Boolean,
        action: WatchdogAction,
    ) {
        val suspect = Build.MANUFACTURER.trim().lowercase() in OEM_SUSPECTS
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_PING_AT, System.currentTimeMillis())
            .putString(KEY_LAST_ACTION, action.slug)
            .putBoolean(KEY_STARTED_DOWN, startedDown)
            .putBoolean(KEY_LISTENER_OK, UdaoNotificationListener.isListenerConnected)
            .putBoolean(KEY_OEM_SUSPECT, suspect)
            .apply()
    }

    companion object {
        private const val UNIQUE_NAME = "udao_capture_health_pinger"
        private const val UNIQUE_PERIODIC_NAME = "udao_capture_health_pinger_periodic"

        /** Shared prefs file (survival bridges read the same names). */
        const val PREFS = "udao_survival"
        const val KEY_LAST_PING_AT = "watchdog_lastPingAt"
        const val KEY_LAST_ACTION = "watchdog_lastAction"
        const val KEY_STARTED_DOWN = "watchdog_startedDown"
        const val KEY_LAST_ESCALATED_AT = "watchdog_lastEscalatedAt"
        const val KEY_OEM_SUSPECT = "watchdog_oemSuspect"
        const val KEY_LISTENER_OK = "watchdog_listenerOk"

        const val TWO_MINUTES_MS = 2L * 60L * 1000L
        const val REPEAT_MINUTES = 30L
        const val REBIND_LATCH_MS = 5_000L
        const val ESCALATION_COOLDOWN_MS = 24L * 60L * 60L * 1000L

        private val OEM_SUSPECTS = setOf(
            "xiaomi", "redmi", "poco", "oppo", "realme", "vivo",
            "iqoo", "huawei", "honor", "oneplus", "samsung",
        )

        /**
         * Schedules a single delayed health check. KEEP policy: if a
         * check is already queued (e.g. boot receiver ran twice) the
         * earlier one wins — never stack pings.
         */
        fun schedule(context: Context, delayMs: Long = TWO_MINUTES_MS) {
            val request = OneTimeWorkRequestBuilder<HealthPinger>()
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.KEEP, request)
        }

        /**
         * Phase-05 backbone: the 30-minute periodic watchdog. KEEP
         * policy — an already-enqueued chain is never replaced, so
         * re-arming (boot, app open) can only ADD the chain if it is
         * missing. Exponential backoff on retries.
         */
        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<HealthPinger>(REPEAT_MINUTES, TimeUnit.MINUTES)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15L, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(
                    UNIQUE_PERIODIC_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
        }
    }
}
