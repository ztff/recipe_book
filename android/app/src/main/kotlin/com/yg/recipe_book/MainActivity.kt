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
                                            "tile" to it.tile,
                                            "alt" to it.alt,
                                        )
                                    },
                                    "droppedLines" to res.dropped.map {
                                        mapOf(
                                            "text" to it.text,
                                            "left" to it.left.toDouble(),
                                            "top" to it.top.toDouble(),
                                            "right" to it.right.toDouble(),
                                            "bottom" to it.bottom.toDouble(),
                                            "score" to it.score.toDouble(),
                                            "tile" to it.tile,
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

        // 备份文件落到 Download 目录，走 MediaStore，不需要存储权限。
        val backup = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yg/backup")
        backup.setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    val src = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    if (src == null || name == null) {
                        result.error("bad_args", "缺少路径或文件名", null)
                    } else {
                        worker.execute {
                            val where = BackupSaver.save(applicationContext, java.io.File(src), name)
                            main.post { result.success(where) }
                        }
                    }
                }
                "list" -> worker.execute {
                    val names = BackupSaver.list(applicationContext)
                    main.post { result.success(names) }
                }
                "delete" -> {
                    val names = call.argument<List<String>>("names") ?: emptyList()
                    worker.execute {
                        val n = BackupSaver.delete(applicationContext, names)
                        main.post { result.success(n) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 图片重编码：步骤图转 JPEG、封面裁缩略图
        val image = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yg/image")
        image.setMethodCallHandler { call, result ->
            val src = call.argument<String>("src")
            val dst = call.argument<String>("dst")
            if (src == null || dst == null) {
                result.error("bad_args", "缺少路径", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "toJpeg" -> worker.execute {
                    val ok = ImageTool.toJpeg(
                        java.io.File(src),
                        java.io.File(dst),
                        call.argument<Int>("quality") ?: 85,
                        call.argument<Int>("maxSide") ?: 1600,
                    )
                    main.post { result.success(ok) }
                }
                "thumbnail" -> worker.execute {
                    val ok = ImageTool.thumbnail(
                        java.io.File(src),
                        java.io.File(dst),
                        call.argument<Int>("side") ?: 400,
                        call.argument<Int>("quality") ?: 85,
                    )
                    main.post { result.success(ok) }
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
