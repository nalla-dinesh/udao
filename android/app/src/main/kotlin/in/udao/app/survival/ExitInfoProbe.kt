// phase-05
// ApplicationExitInfo (API 30+): the OS's own record of why our
// process died the last times. This is the replacement for guessing.
// Below API 30 → empty list (honest absence, no fabrication).
//
// Returned maps (stable contract with the Dart HealthProbeBridge):
//   reasonCode : int    — ApplicationExitInfo.REASON_* constant
//   reason     : String — stable slug ("crash", "anr", "low_memory", …)
//   label      : String — Hinglish one-liner for the dashboard
//   timestamp  : long   — epoch ms of the death
//   pid        : int
package `in`.udao.app.survival

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

object ExitInfoProbe {

    fun lastExits(context: Context, max: Int = 5): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return runCatching {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return emptyList()
            am.getHistoricalProcessExitReasons(context.packageName, 0, max)
                .mapNotNull { info -> info?.let { toMap(it) } }
        }.getOrDefault(emptyList())
    }

    private fun toMap(info: ApplicationExitInfo): Map<String, Any?> = mapOf(
        "reasonCode" to info.reason,
        "reason" to reasonSlug(info.reason),
        "label" to hinglishLabel(info),
        "timestamp" to info.timestamp,
        "pid" to info.pid,
    )

    private fun reasonSlug(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_SIGNALED -> "killed_by_signal"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_OTHER -> "other"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_swipe"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stop"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource_limit"
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        else -> "unknown"
    }

    private fun hinglishLabel(info: ApplicationExitInfo): String =
        when (info.reason) {
            ApplicationExitInfo.REASON_SIGNALED ->
                "System ne process band kiya (signal)"
            ApplicationExitInfo.REASON_LOW_MEMORY ->
                "Memory kam thi, OS ne hata diya"
            ApplicationExitInfo.REASON_CRASH -> "App crash hua tha"
            ApplicationExitInfo.REASON_ANR -> "App respond nahi kar raha tha (ANR)"
            ApplicationExitInfo.REASON_OTHER -> "OS ne process khatam kiya (other)"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "Aapne hi app band ki thi"
            ApplicationExitInfo.REASON_USER_STOPPED -> "Force stop hua tha"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE ->
                "Resource limit cross hui (battery/memory)"
            ApplicationExitInfo.REASON_EXIT_SELF -> "App khud band hua tha"
            else -> "Wajah pata nahi chali"
        }
}
