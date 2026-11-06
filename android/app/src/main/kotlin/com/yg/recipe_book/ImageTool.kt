package com.yg.recipe_book

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import kotlin.math.max

/**
 * 图片重编码。
 *
 * 截图里裁出来的步骤图原来是 PNG，一张 900~1500 KB；同尺寸存成 JPEG q85
 * 只要 120~200 KB，肉眼看不出差别。封面则是整张长截图（1080x13454 这种），
 * 等比压缩会把宽度压到一百多像素，等于把图毁了，所以单独走居中裁切。
 */
object ImageTool {

    /** 等比缩到长边不超过 [maxSide]，存 JPEG。 */
    fun toJpeg(src: File, dst: File, quality: Int, maxSide: Int): Boolean = try {
        val bmp = decodeScaled(src, maxSide) ?: return false
        val long = max(bmp.width, bmp.height)
        val out = if (long > maxSide) {
            val k = maxSide.toFloat() / long
            val w = (bmp.width * k).toInt().coerceAtLeast(1)
            val h = (bmp.height * k).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(bmp, w, h, true)
        } else {
            bmp
        }
        write(out, dst, quality)
        if (out !== bmp) out.recycle()
        bmp.recycle()
        true
    } catch (t: Throwable) {
        false
    }

    /**
     * 从图片中心裁一个 [side]x[side] 的方块存 JPEG，给列表封面用。
     *
     * 长截图等比缩会变成一条细线，裁中心才是列表里真正显示的那块。
     */
    fun thumbnail(src: File, dst: File, side: Int, quality: Int): Boolean = try {
        // 先按 2 的幂降采样，避免 13454 高的图直接解成 58 MB
        val bmp = decodeScaled(src, side * 4) ?: return false
        val s = minOf(bmp.width, bmp.height)
        val x = (bmp.width - s) / 2
        val y = (bmp.height - s) / 2
        val crop = Bitmap.createBitmap(bmp, x, y, s, s)
        val out = Bitmap.createScaledBitmap(crop, side, side, true)
        write(out, dst, quality)
        if (out !== crop) out.recycle()
        if (crop !== bmp) crop.recycle()
        bmp.recycle()
        true
    } catch (t: Throwable) {
        false
    }

    private fun decodeScaled(file: File, target: Int): Bitmap? {
        val probe = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, probe)
        if (probe.outWidth <= 0 || probe.outHeight <= 0) return null
        var sample = 1
        var long = max(probe.outWidth, probe.outHeight)
        while (long / (sample * 2) >= target) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(file.path, opts)
    }

    private fun write(bmp: Bitmap, dst: File, quality: Int) {
        dst.parentFile?.mkdirs()
        dst.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }
    }
}
