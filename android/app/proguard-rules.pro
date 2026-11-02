# ML Kit 的文字识别按语言拆分成可选依赖。
# 本项目只打包中文模型，日文/韩文/天城文等类的引用由插件统一持有，
# 运行期不会实例化，因此对缺失的类只做 dontwarn，不额外打包它们的模型。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.latin.**

# 保留 ML Kit 与插件的实现类，避免被裁剪后运行时报 ClassNotFound
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
