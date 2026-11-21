// phase-03
// Boot restore: after a reboot the system unbinds every notification
// listener; this receiver asks for our binding back and queues one
// health check as a safety net. RECEIVE_BOOT_COMPLETED is declared in
// the manifest since Phase 00.
package `in`.udao.app.capture

import android.service.notification.NotificationListenerService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        Thread {
            try {
                val component = ComponentName(appContext, UdaoNotificationListener::class.java)
                NotificationListenerService.requestRebind(component)
                CaptureLog.bridge("boot: requestRebind issued")
                HealthPinger.schedule(appContext)
                CaptureLog.bridge("boot: health pinger scheduled")
                // Phase 05: re-arm the 30-min periodic watchdog. KEEP
                // policy — if the chain survived the reboot (WorkManager
                // persists it), this is a no-op.
                HealthPinger.schedulePeriodic(appContext)
                CaptureLog.bridge("boot: periodic watchdog ensured")
            } catch (e: Exception) {
                CaptureLog.ioFailure("boot.restore", e)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
