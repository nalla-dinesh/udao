// phase-03
// The write-ahead log — the zero-loss core of UDAO capture.
//
// DESIGN LAW: every notification event is appended (and flushed) to
// this file BEFORE anything else happens. If the process dies one
// microsecond later, the event is still on disk and the Dart side
// replays it on next start. At-least-once semantics — the dedup
// engine absorbs the overlap by contract.
//
// File layout (all under noBackupFilesDir):
//   capture_wal.jsonl     — active log (JSON-lines, one event each)
//   capture_wal.1.jsonl   — first rotation (newer of the two)
//   capture_wal.2.jsonl   — second rotation (oldest; deleted next rotate)
//
// Rotation: when the active file crosses MAX_BYTES we shift
// .1 -> .2 (deleting the old .2), main -> .1 and start a fresh main.
// Two rotations of 2 MB each bounds disk use to ~6 MB worst case.
//
// Sweep: entries older than SEVEN_DAYS_MS are dropped whenever a file
// is rewritten (ack path) — the WAL is a safety net, not an archive.
//
// Threading: append() is synchronous (callers are binder threads and
// the zero-loss ordering "append BEFORE push" is only guaranteed by a
// blocking write). read/ack are dispatched by the bridge onto a
// single background executor so the platform thread never blocks.
package `in`.udao.app.capture

import android.content.Context
import java.io.File
import java.util.concurrent.Executors

object WalWriter {

    const val WAL_FILE = "capture_wal.jsonl"
    const val MAX_BYTES = 2L * 1024L * 1024L // 2 MB per segment
    const val SEVEN_DAYS_MS = 7L * 24L * 60L * 60L * 1000L

    private val io = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "udao-wal-io").apply { isDaemon = true }
    }

    fun ioExecutor() = io

    private fun dir(context: Context): File {
        val f: File = context.applicationContext.noBackupFilesDir
        if (!f.exists()) {
            f.mkdirs()
        }
        return f
    }

    private fun active(context: Context): File = File(dir(context), WAL_FILE)
    private fun rotated(context: Context, n: Int): File =
        File(dir(context), "capture_wal.$n.jsonl")

    /** Appends one JSON line, flushing to disk. Blocking by design. */
    @Synchronized
    fun append(context: Context, jsonLine: String) {
        val file = active(context)
        rotateIfNeeded(context)
        file.appendText(jsonLine + "\n")
        // appendText does open/write/close; the close flushes. An extra
        // explicit fsync is skipped: the only crash window we defend
        // against is process death (OS buffers survive that), not
        // power loss (accepted risk for a 2 MB log).
    }

    /** Rotates when the active segment has crossed the cap. */
    @Synchronized
    private fun rotateIfNeeded(context: Context) {
        val main = active(context)
        if (main.length() < MAX_BYTES) {
            return
        }
        val one = rotated(context, 1)
        val two = rotated(context, 2)
        if (two.exists()) {
            two.delete()
        }
        if (one.exists()) {
            one.renameTo(two)
        }
        main.renameTo(one)
    }

    /**
     * Phase-05: the 7-day sweep callable from the health pinger
     * without any Dart ack (upToTs=0 -> only the age cutoff fires).
     * @Synchronized on the same monitor as append/rotate, so a
     * concurrent capture can never interleave with the rewrite.
     */
    @Synchronized
    fun sweep(context: Context): Int = ack(context, 0L)

    /**
     * All pending lines, oldest first (".2", then ".1", then active).
     * Malformed/partial trailing lines (torn write after a hard kill)
     * are skipped, never crash.
     */
    fun readAll(context: Context): List<String> {
        val files = listOf(rotated(context, 2), rotated(context, 1), active(context))
        val out = ArrayList<String>()
        for (file in files) {
            if (!file.exists()) {
                continue
            }
            val lines = file.readLines()
            for (line in lines) {
                val trimmed = line.trim()
                if (trimmed.isEmpty()) {
                    continue
                }
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
                    continue // torn write — drop, zero-loss is best effort
                }
                out.add(trimmed)
            }
        }
        return out
    }

    /**
     * Drops every entry with ts <= [upToTs] (acked by Dart) and, in
     * the same rewrite, every entry older than 7 days (sweep).
     * Each file is rewritten to a temp sibling and atomically renamed.
     * Returns the number of surviving entries.
     */
    fun ack(context: Context, upToTs: Long): Int {
        val now = System.currentTimeMillis()
        // Sweep threshold: entries strictly older than 7 days die even
        // if they were never acked (the WAL is a safety net, not an
        // archive).
        val cutoff = now - SEVEN_DAYS_MS
        val files = listOf(rotated(context, 2), rotated(context, 1), active(context))
        var survivors = 0
        for (file in files) {
            if (!file.exists()) {
                continue
            }
            val kept = ArrayList<String>()
            for (line in file.readLines()) {
                val trimmed = line.trim()
                if (trimmed.isEmpty()) {
                    continue
                }
                val ts = tsOf(trimmed) ?: continue // unreadable -> drop
                if (ts <= upToTs) {
                    continue // acked
                }
                if (ts < cutoff) {
                    continue // expired (7-day sweep)
                }
                kept.add(trimmed)
                survivors++
            }
            rewrite(file, kept)
        }
        return survivors
    }

    private fun tsOf(jsonLine: String): Long? {
        return try {
            org.json.JSONObject(jsonLine).optLong("ts", -1L).takeIf { it > 0L }
        } catch (_: org.json.JSONException) {
            null
        }
    }

    @Synchronized
    private fun rewrite(file: File, lines: List<String>) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
        if (tmp.length() == 0L) {
            // Nothing survives — an empty WAL segment is pointless.
            file.delete()
            tmp.delete()
            return
        }
        if (!tmp.renameTo(file)) {
            // Rename failed (should not happen on same-dir rename);
            // fall back to a plain copy so ack is never lost.
            file.writeText(tmp.readText())
            tmp.delete()
        }
    }
}
