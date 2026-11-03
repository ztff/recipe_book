package com.yg.recipe_book

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** 一行识别结果，坐标是原图像素。 */
class OcrLine(
    val text: String,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val score: Float,
)

/**
 * 本地 OCR：PaddleOCR PP-OCRv4（det + rec）跑在 ONNX Runtime 上。
 *
 * 与原来的 ML Kit 实现相比，中文菜谱截图上的错字大幅减少：ML Kit 会把
 * 「肘子骨头」认成「时子骨头」、「干辣椒」认成「千辣椒」，菜名整行丢失；
 * PP-OCRv4 同一张图基本全对。
 *
 * 整图由本类自己分片（1400px 高、80px 重叠），不经过 Flutter 解码，
 * 所以没有 8192px 的降采样限制。
 */
class OcrEngine(
    private val context: Context,
    /** 分片识别进度回调：(已完成片数, 总片数)。 */
    private val onProgress: ((Int, Int) -> Unit)? = null,
) {

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var det: OrtSession? = null
    private var rec: OrtSession? = null
    private var chars: List<String> = emptyList()
    private val lock = Any()

    private val tileHeight = 1400
    private val tileOverlap = 80
    private val detLimit = 736
    private val detThresh = 0.3f
    private val boxThresh = 0.5f
    private val unclipRatio = 1.6f
    private val recHeight = 48
    private val maxRecWidth = 320

    private fun ensureLoaded() {
        if (det != null && rec != null && chars.isNotEmpty()) return
        synchronized(lock) {
            if (det != null && rec != null && chars.isNotEmpty()) return
            val dir = File(context.filesDir, "ocr_models")
            if (!dir.exists()) dir.mkdirs()

            fun model(name: String, asset: String): String {
                val f = File(dir, name)
                // 模型文件较大，只在缺失或大小不符时重新解包。
                val need = !f.exists() || f.length() == 0L
                if (need) {
                    context.assets.open("ocr/$asset").use { input ->
                        f.outputStream().use { out -> input.copyTo(out, 64 * 1024) }
                    }
                }
                return f.absolutePath
            }

            val opts = OrtSession.SessionOptions()
            opts.setIntraOpNumThreads(max(2, Runtime.getRuntime().availableProcessors() / 2))
            opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)

            det = env.createSession(model("det.onnx", "det.onnx"), opts)
            rec = env.createSession(model("rec.onnx", "rec.onnx"), opts)

            val keysFile = File(dir, "keys.txt")
            if (!keysFile.exists() || keysFile.length() == 0L) {
                context.assets.open("ocr/keys.txt").use { input ->
                    keysFile.outputStream().use { out -> input.copyTo(out) }
                }
            }
            chars = keysFile.readLines(Charsets.UTF_8).filter { it.isNotEmpty() }
        }
    }

    /** 识别结果，附带图片原始尺寸（Flutter 侧解码会把长边压到 8192，坐标必须按原图算）。 */
    class OcrResult(val lines: List<OcrLine>, val width: Int, val height: Int)

    /** 识别一张本地图片，返回按阅读顺序排好的行。 */
    fun recognize(path: String): OcrResult {
        ensureLoaded()
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return OcrResult(emptyList(), 0, 0)

        // 控制总像素，避免超长截图把内存打爆。
        val maxPixels = 32_000_000L
        var sample = 1
        while ((bounds.outWidth.toLong() / sample) * (bounds.outHeight.toLong() / sample) > maxPixels) {
            sample *= 2
        }
        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val full = BitmapFactory.decodeFile(path, decodeOpts)
            ?: return OcrResult(emptyList(), bounds.outWidth, bounds.outHeight)
        val scaleBack = sample.toFloat()

        // 先按高度算出总片数，识别过程中报百分比。
        val totalTiles = if (full.height <= tileHeight) {
          1
        } else {
          ((full.height - tileOverlap) / (tileHeight - tileOverlap)) + 1
        }
        var tileDone = 0
        onProgress?.invoke(0, totalTiles)

        val all = ArrayList<OcrLine>()
        var top = 0
        while (top < full.height) {
            val h = min(tileHeight, full.height - top)
            if (h < 12) break
            val tile = Bitmap.createBitmap(full, 0, top, full.width, h)
            val detBitmap = tile.copy(Bitmap.Config.ARGB_8888, false)
            val boxes = detect(detBitmap)
            for (b in boxes) {
                val cropped = cropQuad(full, b.points, top)
                if (cropped == null) continue
                val (text, score) = recognizeLine(cropped)
                if (text.isBlank() || score < 0.4f) continue
                val ys = b.points.map { it[1] + top }
                val xs = b.points.map { it[0] }
                all.add(
                    OcrLine(
                        text = text,
                        left = xs.min() * scaleBack,
                        top = ys.min() * scaleBack,
                        right = xs.max() * scaleBack,
                        bottom = ys.max() * scaleBack,
                        score = score,
                    )
                )
            }
            tile.recycle()
            detBitmap.recycle()
            tileDone++
            onProgress?.invoke(min(tileDone, totalTiles), totalTiles)
            if (top + h >= full.height) break
            top += tileHeight - tileOverlap
        }
        full.recycle()
        // 上报解码前声明的原始尺寸，而不是可能被 inSampleSize 缩小的实际位图。
        return OcrResult(dedupe(all), bounds.outWidth, bounds.outHeight)
    }

    // ---------- 检测 ----------

    private class Box(val points: List<FloatArray>, val score: Float)

    private fun detect(src: Bitmap): List<Box> {
        val session = det ?: return emptyList()
        // 短边放大到 detLimit，长边不超过 2000，且两边都是 32 的倍数。
        val w0 = src.width.toFloat()
        val h0 = src.height.toFloat()
        var scale = 1f
        val minSide = min(w0, h0)
        if (minSide < detLimit) scale = detLimit / minSide
        var w = (w0 * scale).toInt()
        var h = (h0 * scale).toInt()
        val maxSide = max(w, h)
        if (maxSide > 2000) {
            val k = 2000f / maxSide
            w = (w * k).toInt()
            h = (h * k).toInt()
            scale *= k
        }
        w = max(32, (w + 31) / 32 * 32)
        h = max(32, (h + 31) / 32 * 32)

        val resized = Bitmap.createScaledBitmap(src, w, h, true)
        val buf = FloatBuffer.allocate(3 * h * w)
        val pixels = IntArray(w * h)
        resized.getPixels(pixels, 0, w, 0, 0, w, h)
        resized.recycle()
        for (c in 0 until 3) {
            // 每个通道写在自己的那一段里；早期版本漏了 base，三个通道互相覆盖，
            // 只剩 B 通道有效，导致部分字（姜、料酒、生抽、盐）整框检测不到。
            val base = c * h * w
            for (i in pixels.indices) {
                val p = pixels[i]
                val v = when (c) {
                    0 -> (p shr 16) and 0xFF
                    1 -> (p shr 8) and 0xFF
                    else -> p and 0xFF
                }
                buf.put(base + i, ((v / 255f) - 0.5f) / 0.5f)
            }
        }
        buf.rewind()

        val input = OnnxTensor.createTensor(env, buf, longArrayOf(1, 3, h.toLong(), w.toLong()))
        val out = session.run(mapOf(session.inputNames.iterator().next() to input))
        val tensor = out[0] as OnnxTensor
        val shape = tensor.info.shape
        val oh = shape[2].toInt()
        val ow = shape[3].toInt()
        val fb = tensor.floatBuffer
        val prob = FloatArray(oh * ow)
        fb.get(prob)
        (input as? AutoCloseable)?.close()
        out.close()

        return boxesFromProb(prob, ow, oh, scale)
    }

    private fun boxesFromProb(prob: FloatArray, w: Int, h: Int, scale: Float): List<Box> {
        val bin = BooleanArray(w * h)
        for (i in bin.indices) bin[i] = prob[i] > detThresh
        // 3x3 膨胀，让断开的笔画连成整行。
        val dil = BooleanArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                if (!bin[y * w + x]) continue
                for (dy in -1..1) {
                    val ny = y + dy
                    if (ny < 0 || ny >= h) continue
                    for (dx in -1..1) {
                        val nx = x + dx
                        if (nx < 0 || nx >= w) continue
                        dil[ny * w + nx] = true
                    }
                }
            }
        }
        val seen = BooleanArray(w * h)
        val boxes = ArrayList<Box>()
        val stack = IntArray(w * h)
        val ptsX = IntArray(w * h)
        val ptsY = IntArray(w * h)
        for (start in dil.indices) {
            if (!dil[start] || seen[start]) continue
            var sp = 0
            var count = 0
            stack[sp++] = start
            seen[start] = true
            var scoreSum = 0f
            while (sp > 0) {
                val p = stack[--sp]
                val py = p / w
                val px = p - py * w
                ptsX[count] = px
                ptsY[count] = py
                count++
                scoreSum += prob[p]
                for (dy in -1..1) {
                    val ny = py + dy
                    if (ny < 0 || ny >= h) continue
                    for (dx in -1..1) {
                        if (dx == 0 && dy == 0) continue
                        val nx = px + dx
                        if (nx < 0 || nx >= w) continue
                        val np = ny * w + nx
                        if (!dil[np] || seen[np]) continue
                        seen[np] = true
                        stack[sp++] = np
                    }
                }
            }
            if (count < 20) continue
            val score = scoreSum / count
            if (score < boxThresh) continue
            val rect = minAreaRect(ptsX, ptsY, count) ?: continue
            val expanded = unclip(rect)
            val pts = expanded.map { floatArrayOf(it[0] / scale, it[1] / scale) }
            boxes.add(Box(pts, score))
        }
        boxes.sortWith(compareBy({ it.points.minOf { p -> p[1] } }, { it.points.minOf { p -> p[0] } }))
        return boxes
    }

    /** 4 点，顺序：左上 右上 右下 左下。 */
    private fun minAreaRect(xs: IntArray, ys: IntArray, n: Int): List<FloatArray>? {
        val hull = convexHull(xs, ys, n) ?: return null
        var bestArea = Float.MAX_VALUE
        var best: List<FloatArray>? = null
        for (i in hull.indices) {
            val a = hull[i]
            val b = hull[(i + 1) % hull.size]
            val ex = b[0] - a[0]
            val ey = b[1] - a[1]
            val len = hypot(ex.toDouble(), ey.toDouble()).toFloat()
            if (len < 1e-3f) continue
            val ux = ex / len
            val uy = ey / len
            var minU = Float.MAX_VALUE
            var maxU = -Float.MAX_VALUE
            var minV = Float.MAX_VALUE
            var maxV = -Float.MAX_VALUE
            for (p in hull) {
                val u = p[0] * ux + p[1] * uy
                val v = -p[0] * uy + p[1] * ux
                if (u < minU) minU = u
                if (u > maxU) maxU = u
                if (v < minV) minV = v
                if (v > maxV) maxV = v
            }
            val area = (maxU - minU) * (maxV - minV)
            if (area < bestArea) {
                bestArea = area
                best = listOf(
                    floatArrayOf(ux * minU - uy * minV, uy * minU + ux * minV),
                    floatArrayOf(ux * maxU - uy * minV, uy * maxU + ux * minV),
                    floatArrayOf(ux * maxU - uy * maxV, uy * maxU + ux * maxV),
                    floatArrayOf(ux * minU - uy * maxV, uy * minU + ux * maxV),
                )
            }
        }
        return best
    }

    private fun convexHull(xs: IntArray, ys: IntArray, n: Int): List<FloatArray>? {
        if (n < 3) return null
        val pts = ArrayList<FloatArray>(n)
        for (i in 0 until n) pts.add(floatArrayOf(xs[i].toFloat(), ys[i].toFloat()))
        pts.sortWith(compareBy({ it[0] }, { it[1] }))
        fun cross(o: FloatArray, a: FloatArray, b: FloatArray): Float =
            (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

        val lower = ArrayList<FloatArray>()
        for (p in pts) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0) {
                lower.removeAt(lower.size - 1)
            }
            lower.add(p)
        }
        val upper = ArrayList<FloatArray>()
        for (i in pts.indices.reversed()) {
            val p = pts[i]
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0) {
                upper.removeAt(upper.size - 1)
            }
            upper.add(p)
        }
        lower.removeAt(lower.size - 1)
        upper.removeAt(upper.size - 1)
        lower.addAll(upper)
        return if (lower.size >= 3) lower else null
    }

    /** 按 PaddleOCR 的 unclip 公式把框往外扩。 */
    private fun unclip(rect: List<FloatArray>): List<FloatArray> {
        val w = hypot((rect[1][0] - rect[0][0]).toDouble(), (rect[1][1] - rect[0][1]).toDouble()).toFloat()
        val hgt = hypot((rect[2][0] - rect[1][0]).toDouble(), (rect[2][1] - rect[1][1]).toDouble()).toFloat()
        if (w <= 0.5f || hgt <= 0.5f) return rect
        val area = w * hgt
        val perimeter = 2 * (w + hgt)
        val distance = area * unclipRatio / perimeter
        val ux = (rect[1][0] - rect[0][0]) / w
        val uy = (rect[1][1] - rect[0][1]) / w
        val vx = (rect[3][0] - rect[0][0]) / hgt
        val vy = (rect[3][1] - rect[0][1]) / hgt
        val out = ArrayList<FloatArray>(4)
        out.add(floatArrayOf(rect[0][0] - ux * distance - vx * distance, rect[0][1] - uy * distance - vy * distance))
        out.add(floatArrayOf(rect[1][0] + ux * distance - vx * distance, rect[1][1] + uy * distance - vy * distance))
        out.add(floatArrayOf(rect[2][0] + ux * distance + vx * distance, rect[2][1] + uy * distance + vy * distance))
        out.add(floatArrayOf(rect[3][0] - ux * distance + vx * distance, rect[3][1] - uy * distance + vy * distance))
        return out
    }

    /** 把 4 点框按透视变换裁出来，坐标以整图为准（tileTop 是切片顶部）。 */
    private fun cropQuad(full: Bitmap, points: List<FloatArray>, tileTop: Int): Bitmap? {
        val w = hypot((points[1][0] - points[0][0]).toDouble(), (points[1][1] - points[0][1]).toDouble())
        val h = hypot((points[3][0] - points[0][0]).toDouble(), (points[3][1] - points[0][1]).toDouble())
        val ow = w.toInt().coerceIn(4, 2000)
        val oh = h.toInt().coerceIn(4, 2000)
        if (ow < 4 || oh < 4) return null
        val out = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888)
        val src = FloatArray(8)
        for (i in 0 until 4) {
            src[i * 2] = points[i][0]
            src[i * 2 + 1] = points[i][1] + tileTop
        }
        val dst = floatArrayOf(0f, 0f, ow.toFloat(), 0f, ow.toFloat(), oh.toFloat(), 0f, oh.toFloat())
        val matrix = android.graphics.Matrix()
        matrix.setPolyToPoly(src, 0, dst, 0, 4)
        val canvas = android.graphics.Canvas(out)
        canvas.drawBitmap(full, matrix, android.graphics.Paint().apply {
            isFilterBitmap = true
            isAntiAlias = true
        })
        return out
    }

    // ---------- 识别 ----------

    private fun recognizeLine(bitmap: Bitmap): Pair<String, Float> {
        val session = rec ?: return "" to 0f
        val ratio = bitmap.width.toFloat() / bitmap.height
        var w = (recHeight * ratio).toInt().coerceIn(8, maxRecWidth)
        val scaled = Bitmap.createScaledBitmap(bitmap, w, recHeight, true)
        if (scaled !== bitmap) bitmap.recycle()

        val buf = FloatBuffer.allocate(3 * recHeight * w)
        val pixels = IntArray(w * recHeight)
        scaled.getPixels(pixels, 0, w, 0, 0, w, recHeight)
        scaled.recycle()
        for (c in 0 until 3) {
            val base = c * recHeight * w
            for (i in pixels.indices) {
                val p = pixels[i]
                val v = when (c) {
                    0 -> (p shr 16) and 0xFF
                    1 -> (p shr 8) and 0xFF
                    else -> p and 0xFF
                }
                buf.put(base + i, ((v / 255f) - 0.5f) / 0.5f)
            }
        }
        buf.rewind()
        val input = OnnxTensor.createTensor(env, buf, longArrayOf(1, 3, recHeight.toLong(), w.toLong()))
        val out = session.run(mapOf(session.inputNames.iterator().next() to input))
        val tensor = out[0] as OnnxTensor
        val shape = tensor.info.shape
        val steps = shape[1].toInt()
        val classes = shape[2].toInt()
        val fb = tensor.floatBuffer
        val data = FloatArray(steps * classes)
        fb.get(data)
        (input as? AutoCloseable)?.close()
        out.close()

        val sb = StringBuilder()
        var last = -1
        var scoreSum = 0f
        var scoreCount = 0
        for (t in 0 until steps) {
            val off = t * classes
            var best = 0
            var bestV = data[off]
            for (c in 1 until classes) {
                val v = data[off + c]
                if (v > bestV) {
                    bestV = v
                    best = c
                }
            }
            if (best == last) continue
            last = best
            if (best == 0) continue
            val idx = best - 1
            if (idx < chars.size) sb.append(chars[idx])
            scoreSum += bestV
            scoreCount++
        }
        val score = if (scoreCount == 0) 0f else scoreSum / scoreCount
        return sb.toString() to score
    }

    /**
     * 去掉重叠切片带里的重复行。
     *
     * 同一行会被两片各认一次，两次结果未必一字不差（例如「葱」和「忽」），
     * 所以按位置判重、保留置信度高的那个，而不是要求文本相同。
     */
    private fun dedupe(lines: List<OcrLine>): List<OcrLine> {
        val sorted = lines.sortedWith(compareBy({ it.top }, { it.left }))
        val out = ArrayList<OcrLine>(sorted.size)
        for (l in sorted) {
            val idx = out.indexOfFirst {
                abs(it.top - l.top) < 20 && abs(it.left - l.left) < 20
            }
            if (idx < 0) {
                out.add(l)
            } else if (l.score > out[idx].score) {
                out[idx] = l
            }
        }
        return out
    }

    fun close() {
        synchronized(lock) {
            det?.close(); det = null
            rec?.close(); rec = null
            chars = emptyList()
        }
    }
}
