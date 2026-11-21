// phase-05
// Device-truth probe: what the OS *actually* thinks of us right now.
// Read-only, try/catch everywhere — a probe that crashes the app is
// worse than a probe that says "pata nahi".
//
// Returned map keys (stable contract with the Dart HealthProbeBridge):
//   ignoringBatteryOptimizations : bool   — exact OS answer
//   powerSaverMode               : bool
//   backgroundRestricted         : bool?  — API 28+; null below
//   standbyBucket                : int?   — API 28+; null = unknown
//   deviceIdle                   : bool   — true only inside doze RIGHT NOW
//
// HONESTY RULE: we never infer a value we could not read. Missing
// reads surface as null and the dashboard shows "nahi pata".
package `in`.udao.app.survival

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager

object PowerStateProbe {

    fun snapshot(context: Context): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val pkg = context.packageName

        val ignoring = runCatching { pm?.isIgnoringBatteryOptimizations(pkg) }.getOrNull()
        val saver = runCatching { pm?.isPowerSaveMode }.getOrNull()
        val idle = runCatching { pm?.isDeviceIdleMode }.getOrNull()

        val restricted: Boolean? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                runCatching {
                    val am = context.getSystemService(Context.ACTIVITY_SERVICE)
                        as? android.app.ActivityManager
                    am?.isBackgroundRestricted
                }.getOrNull()
            } else {
                null
            }

        // Own-bucket query needs no permission on API 28+; guarded anyway.
        val bucket: Int? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                runCatching {
                    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE)
                        as? UsageStatsManager
                    usm?.appStandbyBucket
                }.getOrNull()
            } else {
                null
            }

        return mapOf(
            "ignoringBatteryOptimizations" to (ignoring ?: false),
            "powerSaverMode" to (saver ?: false),
            "backgroundRestricted" to restricted,
            "standbyBucket" to bucket,
            "deviceIdle" to (idle ?: false),
        )
    }
}
