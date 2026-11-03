import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：android/key.properties 提供密码与 keystore 路径（该文件不入库）。
// 在 CI 上由 workflow 从 secrets 还原；本地缺失时自动回退到 debug 签名。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.yg.recipe_book"
    compileSdk = flutter.compileSdkVersion
    // 本项目没有需要 NDK 编译的原生代码（sqlite3 走预编译 .so），
    // 因此不强制 NDK 版本，避免构建机被迫下载 1GB+ 的 NDK。
    // ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yg.recipe_book"
        // ONNX Runtime 的 AAR 自带四个架构的 .so（约 98MB），
        // 不按构建目标裁掉会让每个 APK 都背上全部架构。
        //
        // 注意：--split-per-abi 构建时 Gradle 已经用 splits.abi.filters 指定了架构，
        // 这时再设 ndk.abiFilters 会报 "Conflicting configuration" 直接失败，
        // 所以只有在单架构构建（--target-platform）时才补这一刀。
        val splitPerAbi = project.findProperty("split-per-abi")?.toString() == "true"
        if (!splitPerAbi) {
            ndk {
                abiFilters.clear()
                val targets = (project.findProperty("target-platform") as String?)
                    ?.split(",")
                    ?.map { it.trim() }
                    ?.filter { it.isNotEmpty() }
                    .orEmpty()
                for (t in targets) {
                    when (t) {
                        "android-arm64" -> abiFilters.add("arm64-v8a")
                        "android-arm" -> abiFilters.add("armeabi-v7a")
                        "android-x64" -> abiFilters.add("x86_64")
                    }
                }
            }
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // .onnx 模型不需要二次压缩：压缩后 R8 打包会被解压到临时目录，
    // 首次加载会多花时间，且体积几乎压不动。
    androidResources {
        noCompress += listOf("onnx")
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // PaddleOCR（PP-OCRv4）走 ONNX Runtime 本地推理，模型放在 assets/ocr 里。
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}

