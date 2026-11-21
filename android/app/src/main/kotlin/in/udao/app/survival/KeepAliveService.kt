// phase-05
// Optional user-armed keep-alive foreground service (specialUse FGS).
//
// What it IS: a MIN-importance persistent notice + a 15-minute
// heartbeat that keeps the process warm and re-requests the listener
// binding when the OS drops it — the last-resort lever for phones
// where even the watchdog's component-toggle gets overridden.
//
// What it is NOT: a dataSync/media FGS (banned), an alarm (banned),
// or something the app starts on its own. The USER arms it from the
// health dashboard; it survives task-removal (onTaskRemoved never
// stopSelfs — that is the entire point) and stops only via its notice
// action or the dashboard toggle.
//
// specialUse FGS (Android 14+): declared with the subtype property in
// the manifest; on older versions it degrades to a plain FGS.
package `in`.udao.app.survival

import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ServiceCompat

class KeepAliveService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private val heartbeat: Runnable = object : Runnable {
        override fun run() {
            heartbeatTick()
            handler.postDelayed(this, HEARTBEAT_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                handler.removeCallbacks(heartbeat)
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startKeepAlive()
        }
        return START_STICKY
    }

    private fun startKeepAlive() {
        isRunning = true
        NotificationGateway.ensureChannels(this)
        val stopIntent = PendingIntent.getService(
            this,
            REQUEST_STOP,
            Intent(this, KeepAliveService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationGateway.keepAliveBuilder(
            this,
            "UDAO capture chal raha hai",
            "Bank notifications par nazar rakhne ke liye ye service chahiye. "
                + "Band karne ke liye \"Band karo\" dabao.",
            stopIntent,
        )
        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
        ServiceCompat.startForeground(this, NotificationGateway.ID_KEEP_ALIVE, notification, type)
        handler.removeCallbacks(heartbeat)
        handler.postDelayed(heartbeat, HEARTBEAT_MS)
    }

    /** 15-min tick: nudge the binding if it dropped, record a beat. */
    private fun heartbeatTick() {
        if (!`in`.udao.app.capture.UdaoNotificationListener.isListenerConnected) {
            val component = ComponentName(
                this,
                `in`.udao.app.capture.UdaoNotificationListener::class.java,
            )
            runCatching {
                android.service.notification.NotificationListenerService
                    .requestRebind(component)
            }
        }
        val prefs = getSharedPreferences(HealthBridgePrefs.NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_LAST_BEAT_AT, System.currentTimeMillis())
            .putLong(KEY_BEATS, prefs.getLong(KEY_BEATS, 0L) + 1L)
            .apply()
    }

    /**
     * Android 15+ FGS timeout hook — specialUse has no system timeout
     * today, but if the platform ever fires this we go down quietly
     * (stop foreground, keep process alive for the watchdog to heal).
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        handler.removeCallbacks(heartbeat)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * THE SURVIVAL RULE: swipe-away must NOT kill us (see
     * docs/oem-survival.md truth table). The override stays
     * deliberately empty — the default would tear us down.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        // deliberately empty — never terminate from here
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeat)
        isRunning = false
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "in.udao.app.survival.KEEP_ALIVE_START"
        const val ACTION_STOP = "in.udao.app.survival.KEEP_ALIVE_STOP"
        const val HEARTBEAT_MS = 15L * 60L * 1000L
        private const val REQUEST_STOP = 4201

        /** Beats + last-beat live in the shared survival prefs. */
        const val KEY_LAST_BEAT_AT = "keepalive_lastBeatAt"
        const val KEY_BEATS = "keepalive_beats"

        /** In-process view of the started flag (dashboard toggle state). */
        @Volatile
        var isRunning: Boolean = false
            private set
    }
}

/** Prefs file shared by the survival bridges (single source of names). */
object HealthBridgePrefs {
    const val NAME = "udao_survival"
}
