// phase-06
// On-device AI bridge: MediaPipe GenAI LLM Inference behind our own
// platform channels — no Dart AI plugin, no network, no codegen
// (ADR-0007).
//
// Why a hand-rolled seam (and not flutter_gemma / flutter_edge_ai):
//   * flutter_gemma is DISCONTINUED (final 1.11.4, Oct-2026) and its
//     tree drags in background_downloader (a NETWORK package — banned
//     by ADR-0001) plus Dart native-assets `hooks` (a build mode this
//     project deliberately avoids; the user's toolchain already hit a
//     native-assets cache bug once in Phase 04).
//   * The Kotlin surface here is ~30 calls against the public
//     com.google.mediapipe:tasks-genai API, verified method-by-method
//     against the official docs + the flutter_gemma maintainer's own
//     API notes (session cancel is `cancelGenerateResponseAsync()`,
//     NOT `cancel()`). Everything else in this repo already talks to
//     Kotlin through channels exactly like this one.
//
// Channel contract (mirrored by AiBridge Dart + static_verify §6p):
//   MethodChannel 'udao/ai':
//     "loadModel"      {path, maxTokens, maxImages} -> {sizeBytes}
//     "unload"         {} -> true
//     "isLoaded"       {} -> Bool
//     "createSession"  {temperature, topK} -> {sessionId}
//     "closeSession"   {sessionId} -> true
//     "generate"       {sessionId, prompt} -> true (events on stream)
//     "generateVision" {sessionId, prompt, imagePath} -> true
//     "cancelGenerate" {sessionId} -> true
//   EventChannel 'udao/ai/stream' — maps:
//     {sessionId, type: "token", text}      cumulative text so far
//     {sessionId, type: "done", elapsedMs, totalChars}
//     {sessionId, type: "error", code, message}
//
// Tokens are NOT counted by MediaPipe — Dart estimates chars/4 and
// labels it "estimated" everywhere it is shown (honesty law).
package `in`.udao.app.ai

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

object AiBridge {
    private const val CONTROL = "udao/ai"
    private const val STREAM = "udao/ai/stream"

    // Long edge cap for vision images — Gemma 3n's vision encoder does
    // not benefit from more, and bitmaps are decoded on the inference
    // thread anyway.
    private const val MAX_IMAGE_EDGE = 1024

    private var inference: LlmInference? = null
    private var visionCapable = false
    private val sessions = HashMap<Int, LlmInferenceSession>()
    private val nextSessionId = AtomicInteger(1)

    // One generation at a time, globally — a second generate() while
    // the first streams would corrupt the shared KV cache session.
    @Volatile private var generatingSessionId: Int? = null

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "udao-ai").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun attach(context: Context, engine: FlutterEngine) {
        // Application context only — the engine must never outlive (or
        // leak) a rotated activity.
        contextRef = context.applicationContext
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CONTROL,
        ).setMethodCallHandler { call, result ->
            handle(context, call.method, call.arguments, result)
        }
        EventChannel(engine.dartExecutor.binaryMessenger, STREAM)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                        sink = events
                    }

                    override fun onCancel(args: Any?) {
                        sink = null
                    }
                },
            )
    }

    // ---- control surface ------------------------------------------------

    private fun handle(
        context: Context,
        method: String,
        rawArgs: Any?,
        result: MethodChannel.Result,
    ) {
        val args = rawArgs as? Map<*, *> ?: emptyMap<Any, Any>()
        when (method) {
            "loadModel" -> executor.execute {
                runCatching { loadModel(args) }
                    .onSuccess { result.success(it) }
                    .onFailure { t ->
                        result.error("UDAO_AI_LOAD_FAILED", t.message ?: "load failed", null)
                    }
            }
            "unload" -> executor.execute {
                runCatching { unloadLocked() }
                    .onSuccess { result.success(true) }
                    .onFailure { t ->
                        result.error("UDAO_AI_UNLOAD_FAILED", t.message ?: "unload failed", null)
                    }
            }
            "isLoaded" -> result.success(inference != null)
            "createSession" -> executor.execute {
                runCatching { createSession(args) }
                    .onSuccess { result.success(it) }
                    .onFailure { t ->
                        result.error("UDAO_AI_SESSION_FAILED", t.message ?: "session failed", null)
                    }
            }
            "closeSession" -> executor.execute {
                val id = (args["sessionId"] as? Number)?.toInt() ?: -1
                runCatching { closeSessionLocked(id) }
                    .onSuccess { result.success(true) }
                    .onFailure { t ->
                        result.error("UDAO_AI_SESSION_FAILED", t.message ?: "close failed", null)
                    }
            }
            "generate" -> executor.execute {
                startGeneration(args, imagePath = null, result = result)
            }
            "generateVision" -> executor.execute {
                startGeneration(args, imagePath = args["imagePath"] as? String, result = result)
            }
            "cancelGenerate" -> executor.execute {
                val id = (args["sessionId"] as? Number)?.toInt() ?: -1
                runCatching { cancelLocked(id) }
                    .onSuccess { result.success(true) }
                    .onFailure { t ->
                        result.error("UDAO_AI_CANCEL_FAILED", t.message ?: "cancel failed", null)
                    }
            }
            else -> result.notImplemented()
        }
    }

    // ---- engine + sessions (executor thread only) ------------------------

    private fun loadModel(args: Map<*, *>): Map<String, Any> {
        val path = args["path"] as? String
            ?: throw IllegalArgumentException("path missing")
        val file = File(path)
        if (!file.isFile) {
            throw IllegalArgumentException("model file not found: $path")
        }
        unloadLocked()
        val maxTokens = (args["maxTokens"] as? Number)?.toInt() ?: 1024
        val maxImages = (args["maxImages"] as? Number)?.toInt() ?: 0
        visionCapable = maxImages > 0
        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(file.absolutePath)
            .setMaxTokens(maxTokens)
            .apply { if (maxImages > 0) setMaxNumImages(maxImages) }
            .build()
        inference = LlmInference.createFromOptions(contextRef, options)
        return mapOf(
            "ok" to true,
            "sizeBytes" to file.length(),
        )
    }

    // Kept as the application context handed in by attach() so the
    // engine never outlives (or leaks) a rotated activity.
    private lateinit var contextRef: android.content.Context

    private fun unloadLocked() {
        val ids = sessions.keys.toList()
        for (id in ids) {
            runCatching { sessions.remove(id)?.close() }
        }
        generatingSessionId = null
        inference?.let { current -> runCatching { current.close() } }
        inference = null
        visionCapable = false
    }

    private fun createSession(args: Map<*, *>): Map<String, Any> {
        val engine = inference
            ?: throw IllegalStateException("model not loaded")
        val temperature = (args["temperature"] as? Number)?.toDouble() ?: 0.8
        val topK = (args["topK"] as? Number)?.toInt() ?: 40
        val builder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
            .setTemperature(temperature.toFloat())
            .setTopK(topK)
        if (visionCapable) {
            builder.setGraphOptions(
                GraphOptions.builder().setEnableVisionModality(true).build(),
            )
        }
        val session = LlmInferenceSession.createFromOptions(engine, builder.build())
        val id = nextSessionId.getAndIncrement()
        synchronized(sessions) { sessions[id] = session }
        return mapOf("sessionId" to id)
    }

    private fun closeSessionLocked(id: Int) {
        val session = synchronized(sessions) { sessions.remove(id) }
        session?.close()
        if (generatingSessionId == id) {
            generatingSessionId = null
        }
    }

    private fun cancelLocked(id: Int) {
        val session = synchronized(sessions) { sessions[id] }
        if (session != null) {
            // The ONLY real stop handle in tasks-genai — verified name
            // against the MediaPipe sources (see file header).
            session.cancelGenerateResponseAsync()
        }
    }

    private fun startGeneration(
        args: Map<*, *>,
        imagePath: String?,
        result: MethodChannel.Result,
    ) {
        val engine = inference
        if (engine == null) {
            result.error("UDAO_AI_NOT_LOADED", "model not loaded", null)
            return
        }
        val id = (args["sessionId"] as? Number)?.toInt() ?: -1
        val session = synchronized(sessions) { sessions[id] }
        if (session == null) {
            result.error("UDAO_AI_SESSION_FAILED", "no session $id", null)
            return
        }
        if (generatingSessionId != null) {
            result.error("UDAO_AI_BUSY", "a generation is already running", null)
            return
        }
        val prompt = args["prompt"] as? String
        if (prompt.isNullOrEmpty()) {
            result.error("UDAO_AI_BAD_ARGS", "prompt missing", null)
            return
        }
        if (imagePath != null && !visionCapable) {
            result.error(
                "UDAO_AI_NO_VISION",
                "model was not loaded for image input",
                null,
            )
            return
        }
        generatingSessionId = id
        result.success(true)
        val startedAt = System.currentTimeMillis()
        runCatching {
            session.addQueryChunk(prompt)
            if (imagePath != null) {
                session.addImage(decodeCapped(imagePath))
            }
            session.generateResponseAsync { partial, done ->
                if (done) {
                    val elapsed = System.currentTimeMillis() - startedAt
                    emit(
                        mapOf(
                            "sessionId" to id,
                            "type" to "done",
                            "elapsedMs" to elapsed,
                            "totalChars" to ((partial as? String)?.length ?: 0),
                        ),
                    )
                    generatingSessionId = null
                } else {
                    emit(
                        mapOf(
                            "sessionId" to id,
                            "type" to "token",
                            "text" to (partial as? String ?: ""),
                        ),
                    )
                }
            }
        }.onFailure { t ->
            emittingFailure(id, t)
        }
    }

    private fun emittingFailure(id: Int, t: Throwable) {
        generatingSessionId = null
        val code = when {
            t is OutOfMemoryError ||
                (t.message?.contains("memory", ignoreCase = true) == true) -> "oom"
            else -> "generation-error"
        }
        emit(
            mapOf(
                "sessionId" to id,
                "type" to "error",
                "code" to code,
                "message" to (t.message ?: "generation failed"),
            ),
        )
    }

    private fun decodeCapped(path: String) =
        BitmapImageBuilder(decodeCappedBitmap(path)).build()

    private fun decodeCappedBitmap(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (
            (bounds.outWidth / sample > MAX_IMAGE_EDGE ||
                bounds.outHeight / sample > MAX_IMAGE_EDGE) && sample < 16
        ) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
            ?: throw IllegalArgumentException("unreadable image: $path")
    }

    // ---- event plumbing ---------------------------------------------------

    private fun emit(payload: Map<String, Any?>) {
        // EventChannel sinks must be touched on the platform thread;
        // MediaPipe calls back on its own worker.
        main.post { sink?.success(payload) }
    }
}
