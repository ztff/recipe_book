package com.yg.recipe_book

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "yg/ocr"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var engine: OcrEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognize" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "缺少图片路径", null)
                            return@setMethodCallHandler
                        }
                        worker.execute {
                            try {
                                val ocr = engine ?: OcrEngine(applicationContext) { done, total ->
                                    main.post {
                                        try {
                                            channel.invokeMethod(
                                                "progress",
                                                mapOf("done" to done, "total" to total),
                                            )
                                        } catch (_: Throwable) {
                                        }
                                    }
                                }.also { engine = it }
                                val res = ocr.recognize(path)
                                val payload = mapOf(
                                    "width" to res.width,
                                    "height" to res.height,
                                    "lines" to res.lines.map {
                                        mapOf(
                                            "text" to it.text,
                                            "left" to it.left.toDouble(),
                                            "top" to it.top.toDouble(),
                                            "right" to it.right.toDouble(),
                                            "bottom" to it.bottom.toDouble(),
                                            "score" to it.score.toDouble(),
                                        )
                                    },
                                )
                                main.post { result.success(payload) }
                            } catch (t: Throwable) {
                                main.post { result.error("ocr_failed", t.message ?: t.toString(), null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        engine?.close()
        engine = null
        worker.shutdown()
        super.onDestroy()
    }
}
