// phase-05
// The `udao/survival` channel: device-truth probes + the keep-alive
// lever + battery-optimization intents + OEM deep links. Mirrors the
// capture bridge's style (no engine state, everything appContext).
//
// Channel contract (stable; mirrored by SurvivalProbeBridge in Dart):
//   getPowerState() -> map (see PowerStateProbe)
//   getExitInfos() -> list of maps (see ExitInfoProbe)
//   getWatchdogSnapshot() -> map (HealthPinger prefs mirror)
//   getKeepAliveState() -> {running, lastBeatAt, beats}
//   startKeepAlive() -> bool
//   stopKeepAlive() -> bool
//   postNotification({id,title,body}) -> bool   (id whitelist!)
//   openBatteryOptimizationSettings() -> bool   (the LIST screen)
//   requestIgnoreBatteryOptimizations() -> bool (power flavor only)
//   openAppDetails() -> bool
//   openOemScreen({component}) -> bool          (try/catch, no crash)
//
// Play vs power (ADR-0002 / ADR-0006): the direct
// ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog needs the
// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission, which Play policy
// restricts. The play flavor never declares it and this bridge
// double-guards by flavor; play users get the settings LIST screen.
package `in`.udao.app.survival

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import `in`.udao.app.BuildConfig
import `in`.udao.app.capture.HealthPinger

object SurvivalBridge {

    const val CHANNEL_NAME = "udao/survival"

    private const val METHOD_POWER_STATE = "getPowerState"
    private const val METHOD_EXIT_INFOS = "getExitInfos"
    private const val METHOD_WATCHDOG = "getWatchdogSnapshot"
    private const val METHOD_KEEP_ALIVE_STATE = "getKeepAliveState"
    private const val METHOD_START_KEEP_ALIVE = "startKeepAlive"
    private const val METHOD_STOP_KEEP_ALIVE = "stopKeepAlive"
    private const val METHOD_POST_NOTIFICATION = "postNotification"
    private const val METHOD_OPEN_BATTERY_LIST = "openBatteryOptimizationSettings"
    private const val METHOD_REQUEST_IGNORE_BATT = "requestIgnoreBatteryOptimizations"
    private const val METHOD_OPEN_APP_DETAILS = "openAppDetails"
    private const val METHOD_OPEN_OEM_SCREEN = "openOemScreen"

    fun attach(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_POWER_STATE ->
                    runCatching { PowerStateProbe.snapshot(appContext) }
                        .onSuccess { result.success(it) }
                        .onFailure {
                            result.error("UDAO_SURVIVAL_ERROR", it.message ?: "unknown", null)
                        }

                METHOD_EXIT_INFOS ->
                    runCatching { ExitInfoProbe.lastExits(appContext) }
                        .onSuccess { result.success(it) }
                        .onFailure {
                            result.error("UDAO_SURVIVAL_ERROR", it.message ?: "unknown", null)
                        }

                METHOD_WATCHDOG -> result.success(watchdogSnapshot(appContext))

                METHOD_KEEP_ALIVE_STATE -> result.success(keepAliveState(appContext))

                METHOD_START_KEEP_ALIVE -> {
                    runCatching {
                        ContextCompat.startForegroundService(
                            appContext,
                            Intent(appContext, KeepAliveService::class.java)
                                .setAction(KeepAliveService.ACTION_START),
                        )
                    }.onSuccess { result.success(true) }
                        .onFailure { result.success(false) }
                }

                METHOD_STOP_KEEP_ALIVE -> {
                    appContext.stopService(
                        Intent(appContext, KeepAliveService::class.java),
                    )
                    result.success(true)
                }

                METHOD_POST_NOTIFICATION -> {
                    val id = call.argument<Int>("id") ?: NotificationGateway.ID_ESCALATION
                    val title = call.argument<String>("title") ?: "UDAO"
                    val body = call.argument<String>("body") ?: ""
                    // Whitelist: the UI may only ever fire the two
                    // health IDs — no arbitrary notification surface.
                    val allowed = id == NotificationGateway.ID_ESCALATION ||
                        id == NotificationGateway.ID_GAP_ALERT
                    if (!allowed) {
                        result.error("UDAO_SURVIVAL_ERROR", "notification id not allowed", null)
                    } else {
                        NotificationGateway.postHealth(appContext, id, title, body)
                        result.success(true)
                    }
                }

                METHOD_OPEN_BATTERY_LIST -> {
                    // Play-safe: opens the SYSTEM LIST of all apps'
                    // battery states; no special permission needed.
                    runCatching {
                        appContext.startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }.onSuccess { result.success(true) }
                        .onFailure { result.success(false) }
                }

                METHOD_REQUEST_IGNORE_BATT -> {
                    if (BuildConfig.FLAVOR != "power") {
                        // Double guard: play builds never even try.
                        result.success(false)
                    } else {
                        runCatching {
                            appContext.startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:${appContext.packageName}"),
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        }.onSuccess { result.success(true) }
                            .onFailure { result.success(false) }
                    }
                }

                METHOD_OPEN_APP_DETAILS -> {
                    runCatching {
                        appContext.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:${appContext.packageName}"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }.onSuccess { result.success(true) }
                        .onFailure { result.success(false) }
                }

                METHOD_OPEN_OEM_SCREEN -> {
                    // OEM deep link from the guide data: "pkg/cls".
                    // Undocumented screens — a miss must never crash;
                    // the Dart side always offers the manual fallback.
                    val flat = call.argument<String>("component")
                    val component = flat?.let { ComponentName.unflattenFromString(it) }
                    if (component == null) {
                        result.success(false)
                    } else {
                        runCatching {
                            appContext.startActivity(
                                Intent().setComponent(component)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        }.onSuccess { result.success(true) }
                            .onFailure { result.success(false) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun watchdogSnapshot(ctx: Context): Map<String, Any?> {
        val prefs = ctx.getSharedPreferences(HealthPinger.PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "lastPingAt" to prefs.getLong(HealthPinger.KEY_LAST_PING_AT, 0L),
            "lastAction" to (prefs.getString(HealthPinger.KEY_LAST_ACTION, "none") ?: "none"),
            "startedDown" to prefs.getBoolean(HealthPinger.KEY_STARTED_DOWN, false),
            "listenerOk" to prefs.getBoolean(HealthPinger.KEY_LISTENER_OK, false),
            "lastEscalatedAt" to prefs.getLong(HealthPinger.KEY_LAST_ESCALATED_AT, 0L),
            "oemSuspect" to prefs.getBoolean(HealthPinger.KEY_OEM_SUSPECT, false),
        )
    }

    private fun keepAliveState(ctx: Context): Map<String, Any?> {
        val prefs = ctx.getSharedPreferences(HealthBridgePrefs.NAME, Context.MODE_PRIVATE)
        return mapOf(
            "running" to KeepAliveService.isRunning,
            "lastBeatAt" to prefs.getLong(KeepAliveService.KEY_LAST_BEAT_AT, 0L),
            "beats" to prefs.getLong(KeepAliveService.KEY_BEATS, 0L),
        )
    }
}
