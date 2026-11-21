// `in` is a Kotlin hard keyword (ranges/for-loops), so the first
// package segment must be escaped with backticks. The compiled
// (JVM/manifest) package name is exactly `in.udao.app` — namespace,
// R class and BuildConfig are unaffected. Every Kotlin file in this
// repo uses this exact declaration; do NOT "clean it up".
package `in`.udao.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import `in`.udao.app.ai.AiBridge
import `in`.udao.app.capture.CaptureBridge
import `in`.udao.app.capture.HealthPinger
import `in`.udao.app.survival.SurvivalBridge

/**
 * UDAO entry activity.
 *
 * Hosts the `udao/platform` MethodChannel — a read-only "who am I
 * running on" surface. Dart uses it for OEM detection (manufacturer +
 * brand drive the Phase 05 survival matrix: Poco/Redmi map to Xiaomi,
 * iQOO to vivo, …) and for flavor gating (play vs power).
 *
 * Channel contract (mirrored by AppConstants in Dart):
 *   method "getDeviceInfo" -> {
 *     "appFlavor":      String  // "play" | "power" | "none"
 *     "manufacturer":   String  // Build.MANUFACTURER
 *     "brand":          String  // Build.BRAND
 *     "sdkInt":         Int     // Build.VERSION.SDK_INT
 *     "model":          String  // Build.MODEL (phase 05)
 *     "versionRelease": String  // Build.VERSION.RELEASE (phase 05)
 *     "isEmulator":     Bool    // best-effort fingerprint check
 *     "totalRamMb":     Int     // ActivityManager total (phase 06:
 *                              // model tiering — verified via our own
 *                              // channel, not device_info_plus, whose
 *                              // RAM field names drift between majors)
 *   }
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Phase 05: (re)arm the 30-min periodic watchdog. KEEP policy —
        // a surviving chain is left alone; a fresh install gets armed.
        runCatching { HealthPinger.schedulePeriodic(applicationContext) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UdaoChannel.attach(this, flutterEngine)
        // Phase 03: notification capture bridge (live stream + control
        // surface — see capture/CaptureBridge.kt for the contract).
        CaptureBridge.attach(this, flutterEngine)
        // Phase 05: survival bridge (probes, keep-alive lever, battery
        // + OEM intents — see survival/SurvivalBridge.kt).
        SurvivalBridge.attach(this, flutterEngine)
        // Phase 06: on-device AI bridge (MediaPipe LLM Inference —
        // text/vision sessions over 'udao/ai', see ai/AiBridge.kt).
        AiBridge.attach(this, flutterEngine)
    }

    private object UdaoChannel {
        private const val CHANNEL_NAME = "udao/platform"
        private const val METHOD_DEVICE_INFO = "getDeviceInfo"

        fun attach(context: Context, engine: FlutterEngine) {
            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                CHANNEL_NAME,
            ).setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_DEVICE_INFO -> {
                        runCatching { deviceInfo(context) }
                            .onSuccess { info -> result.success(info) }
                            .onFailure { throwable ->
                                result.error(
                                    "UDAO_PLATFORM_ERROR",
                                    throwable.message ?: "unknown error",
                                    null,
                                )
                            }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun deviceInfo(context: Context): Map<String, Any> = mapOf(
            "appFlavor" to (BuildConfig.FLAVOR.ifEmpty { "none" }),
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "sdkInt" to Build.VERSION.SDK_INT,
            "model" to Build.MODEL,
            "versionRelease" to Build.VERSION.RELEASE,
            "isEmulator" to isEmulator(),
            "totalRamMb" to totalRamMb(context),
        )

        /** Total physical RAM, whole MBs (ActivityManager.MemoryInfo
         *  is a public API since level 16 — zero drift risk). */
        private fun totalRamMb(context: Context): Int = runCatching {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            (memoryInfo.totalMem / (1024L * 1024L)).toInt()
        }.getOrDefault(0)

        /** Standard best-effort emulator fingerprint (never security). */
        private fun isEmulator(): Boolean {
            val fingerprint = Build.FINGERPRINT?.lowercase() ?: ""
            val model = Build.MODEL?.lowercase() ?: ""
            return fingerprint.contains("generic") ||
                fingerprint.contains("unknown") ||
                fingerprint.contains("emulator") ||
                fingerprint.contains("sdk_gphone") ||
                model.contains("emulator") ||
                model.contains("android sdk built for")
        }
    }
}
