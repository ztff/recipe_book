package com.yg.recipe_book

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * 把备份 zip 放到用户能自己找到的地方。
 *
 * Android 10 起写 Download 目录要走 MediaStore，好处是不用任何存储权限；
 * 更老的系统退到应用外部私有目录，同样不需要权限，代价是卸载会一起清掉。
 * 两种情况都不涉及网络，也不申请 MANAGE_EXTERNAL_STORAGE。
 */
object BackupSaver {

    private const val SUBDIR = "recipe_book_backup"
    private const val MIME = "application/zip"

    /** 复制 [src] 进去，返回给人看的位置；失败返回 null。 */
    fun save(ctx: Context, src: File, name: String): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, MIME)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/" + SUBDIR,
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = ctx.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                null
            } else {
                val ok = resolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { it.copyTo(out) }
                    true
                } ?: false
                if (!ok) {
                    resolver.delete(uri, null, null)
                    null
                } else {
                    val done = ContentValues().apply {
                        put(MediaStore.Downloads.IS_PENDING, 0)
                    }
                    resolver.update(uri, done, null, null)
                    "Download/" + SUBDIR + "/" + name
                }
            }
        } else {
            val dst = File(legacyDir(ctx), name)
            src.inputStream().use { i -> dst.outputStream().use { o -> i.copyTo(o) } }
            dst.absolutePath
        }
    } catch (t: Throwable) {
        null
    }

    /** 已有备份，按名字倒序（新的在前）。每项含文件名和字节数。 */
    fun list(ctx: Context): List<Map<String, Any>> = try {
        val out = ArrayList<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ctx.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(
                    MediaStore.Downloads.DISPLAY_NAME,
                    MediaStore.Downloads.SIZE,
                ),
                MediaStore.Downloads.RELATIVE_PATH + " LIKE ?",
                arrayOf("%" + SUBDIR + "%"),
                MediaStore.Downloads.DISPLAY_NAME + " DESC",
            )?.use { cur ->
                while (cur.moveToNext()) {
                    val n = cur.getString(0) ?: continue
                    if (!n.startsWith("recipe_backup_") || !n.endsWith(".zip")) continue
                    out.add(mapOf("name" to n, "size" to cur.getLong(1)))
                }
            }
        } else {
            val files = (legacyDir(ctx).listFiles() ?: emptyArray())
                .filter { it.name.startsWith("recipe_backup_") && it.name.endsWith(".zip") }
                .sortedByDescending { it.name }
            for (f in files) out.add(mapOf("name" to f.name, "size" to f.length()))
        }
        out
    } catch (t: Throwable) {
        emptyList()
    }

    /** 删掉指定的备份，返回真正删掉的个数。 */
    fun delete(ctx: Context, names: List<String>): Int {
        if (names.isEmpty()) return 0
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var n = 0
                for (name in names) {
                    n += ctx.contentResolver.delete(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        MediaStore.Downloads.DISPLAY_NAME + "=? AND " +
                            MediaStore.Downloads.RELATIVE_PATH + " LIKE ?",
                        arrayOf(name, "%" + SUBDIR + "%"),
                    )
                }
                n
            } else {
                var n = 0
                for (name in names) {
                    if (File(legacyDir(ctx), name).delete()) n++
                }
                n
            }
        } catch (t: Throwable) {
            0
        }
    }

    private fun legacyDir(ctx: Context): File {
        val base = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        val dir = File(base, "backup")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }
}
