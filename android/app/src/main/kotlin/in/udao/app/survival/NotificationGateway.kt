// phase-05
// The app's ONLY local-notification poster (Kotlin side, zero extra
// Flutter plugins). Everything user-visible from the background —
// watchdog escalation, gap alerts surfaced on open, the keep-alive
// service notice — flows through here so channel ids, priorities and
// copy stay in one auditable place.
//
// Channels:
//   capture_service (LOW)  — the optional keep-alive FGS notice
//   capture_health (HIGH)  — "capture ruk gaya, 1 tap mein theek karo"
//
// No raw notification/SMS text ever crosses this boundary — titles
// and bodies are static l10n-style strings decided HERE.
package `in`.udao.app.survival

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

object NotificationGateway {

    const val CHANNEL_SERVICE = "capture_service"
    const val CHANNEL_HEALTH = "capture_health"

    const val ID_KEEP_ALIVE = 1001
    const val ID_ESCALATION = 1002
    const val ID_GAP_ALERT = 1003

    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_SERVICE,
                "Background service",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "UDAO background capture notice"
                setShowBadge(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_HEALTH,
                "Capture health",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Warnings when capture stops working"
            },
        )
    }

    fun postHealth(
        context: Context,
        id: Int,
        title: String,
        body: String,
    ) {
        runCatching {
            ensureChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, build(context, CHANNEL_HEALTH, title, body, clickable = true))
        }
    }

    /** Builds the persistent keep-alive notice (STOP action added by the service). */
    fun keepAliveBuilder(
        context: Context,
        title: String,
        body: String,
        stopIntent: PendingIntent,
    ): android.app.Notification =
        runCatching {
            ensureChannels(context)
            NotificationCompat.Builder(context, CHANNEL_SERVICE)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setOngoing(true)
                .setShowWhen(false)
                .setContentIntent(contentIntent(context))
                .addAction(0, "Band karo", stopIntent)
                .build()
        }.getOrElse {
            NotificationCompat.Builder(context, CHANNEL_SERVICE)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setOngoing(true)
                .build()
        }

    private fun build(
        context: Context,
        channelId: String,
        title: String,
        body: String,
        clickable: Boolean,
    ): android.app.Notification =
        NotificationCompat.Builder(context, channelId)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(if (clickable) contentIntent(context) else null)
            .build()

    /** Opens the app (launcher intent) — routing to the health screen
     *  stays an in-app concern; no view-intent/deep-link plumbing. */
    private fun contentIntent(context: Context): PendingIntent {
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?: Intent()
        return PendingIntent.getActivity(
            context,
            49101,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
