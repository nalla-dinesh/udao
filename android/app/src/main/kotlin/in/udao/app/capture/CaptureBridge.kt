// phase-03
// The Flutter <-> native capture boundary.
//
//   EventChannel  "udao/capture/stream"   live events only (WAL replay
//                                           is Dart-driven via control)
//   MethodChannel "udao/capture/control"  getWAL / ackWAL / status /
//                                           rebind / settings / toggle /
//                                           pushAllowlist
//
// Channel + method names are LOCKED by test/features/capture/
// bridge_contract_test.dart (string-constant parity on both sides) —
// rename here, the test breaks, by design.
//
// File IO never touches the platform thread: getWAL/ackWAL hop to
// WalWriter's single background executor and results are posted back
// to the main looper.
package `in`.udao.app.capture

import android.service.notification.NotificationListenerService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

object CaptureBridge {

    const val EVENT_CHANNEL = "udao/capture/stream"
    const val CONTROL_CHANNEL = "udao/capture/control"

    private const val METHOD_GET_WAL = "getWAL"
    private const val METHOD_ACK_WAL = "ackWAL"
    private const val METHOD_STATUS = "listenerStatus"
    private const val METHOD_REBIND = "requestRebind"
    private const val METHOD_OPEN_SETTINGS = "openListenerSettings"
    private const val METHOD_REBIND_TOGGLE = "rebindViaToggle"
    private const val METHOD_PUSH_ALLOWLIST = "pushAllowlist"

    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(context: Context, engine: FlutterEngine) {
        appContext = context.applicationContext

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    UdaoNotificationListener.engineRunning = events != null
                    UdaoNotificationListener.liveSink = events
                    CaptureLog.bridge("stream listened")
                }

                override fun onCancel(arguments: Any?) {
                    UdaoNotificationListener.engineRunning = false
                    UdaoNotificationListener.liveSink = null
                    CaptureLog.bridge("stream cancelled")
                }
            })

        MethodChannel(engine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                // Every branch catches; the channel boundary never throws
                // raw exceptions into Dart.
                runCatching {
                    when (call.method) {
                        METHOD_GET_WAL -> getWal(result)
                        METHOD_ACK_WAL -> ackWal(call.arguments, result)
                        METHOD_STATUS -> status(result)
                        METHOD_REBIND -> rebind(result)
                        METHOD_OPEN_SETTINGS -> openListenerSettings(result)
                        METHOD_REBIND_TOGGLE -> rebindViaToggle(result)
                        METHOD_PUSH_ALLOWLIST -> pushAllowlist(call.arguments, result)
                        else -> result.notImplemented()
                    }
                }.onFailure { throwable ->
                    result.error(
                        "UDAO_CAPTURE_ERROR",
                        throwable.message ?: "unknown capture error",
                        null,
                    )
                }
            }
    }

    // ---- control methods ------------------------------------------------

    private fun getWal(result: MethodChannel.Result) {
        WalWriter.ioExecutor().execute {
            val lines = runCatching { WalWriter.readAll(appContext) }
                .getOrElse { emptyList() }
            mainHandler.post { result.success(lines) }
        }
    }

    private fun ackWal(arguments: Any?, result: MethodChannel.Result) {
        val upToTs = (arguments as? Number)?.toLong()
            ?: throw IllegalArgumentException("ackWAL expects a millisecond timestamp")
        WalWriter.ioExecutor().execute {
            val survivors = runCatching { WalWriter.ack(appContext, upToTs) }.getOrDefault(0)
            mainHandler.post { result.success(survivors) }
        }
    }

    private fun status(result: MethodChannel.Result) {
        val component = ComponentName(appContext, UdaoNotificationListener::class.java)
        val enabled = appContext.packageManager
            .getComponentEnabledSetting(component) !=
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        result.success(
            mapOf(
                "connected" to UdaoNotificationListener.isListenerConnected,
                "lastEventAt" to UdaoNotificationListener.lastEventAt,
                "componentEnabled" to enabled,
            ),
        )
    }

    private fun rebind(result: MethodChannel.Result) {
        // The ONLY safe rebind primitive: static requestRebind with an
        // explicit component. Safe pre-connect, post-disconnect, always.
        val component = ComponentName(appContext, UdaoNotificationListener::class.java)
        NotificationListenerService.requestRebind(component)
        CaptureLog.bridge("requestRebind issued")
        result.success(true)
    }

    private fun openListenerSettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
        result.success(true)
    }

    private fun rebindViaToggle(result: MethodChannel.Result) {
        // Documented recovery workaround for a stuck listener: disable
        // + re-enable the component (without killing the app process),
        // then ask the system to rebind. The toggle makes the system
        // tear down and recreate the binding when a plain requestRebind
        // has stopped working (seen on some MIUI/vivo builds).
        val pm = appContext.packageManager
        val component = ComponentName(appContext, UdaoNotificationListener::class.java)
        pm.setComponentEnabledSetting(
            component,
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            android.content.pm.PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            component,
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            android.content.pm.PackageManager.DONT_KILL_APP,
        )
        NotificationListenerService.requestRebind(component)
        CaptureLog.bridge("rebind via component toggle issued")
        result.success(true)
    }

    private fun pushAllowlist(arguments: Any?, result: MethodChannel.Result) {
        val json = arguments as? String
            ?: throw IllegalArgumentException("pushAllowlist expects a JSON string")
        val installed = UdaoNotificationListener.installAllowlist(json)
        if (installed) {
            // Cache so the listener has it on next boot without the
            // engine having run first.
            WalWriter.ioExecutor().execute {
                runCatching {
                    val file = File(appContext.noBackupFilesDir, "allowlist.json")
                    file.writeText(json)
                }
            }
        }
        result.success(installed)
    }
}
