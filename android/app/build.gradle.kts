import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：从 android/key.properties 读（该文件被 .gitignore 忽略，不进版本库）。
// 没有这个文件时退回 debug 签名，这样新克隆的工程不配密钥也能直接 flutter run / build。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.fangzi.qustschedule"
    // Flutter 3.47 默认是 36，但本机 SDK 只装了 android-37.0（build-tools 36.0.0 已装）。
    // 编译 SDK 允许高于默认值，所以这里用 37；装了 API 36 后可改回 flutter.compileSdkVersion。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fangzi.qustschedule"
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
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 就用自己那把钥匙签；没有就退回 debug 签名
            // （能装能用，但换了机器就不能覆盖升级）。
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

// ---------------------------------------------------------------------------
// 产物命名：flutter-apk/青科课表通_v<版本号>[-abi].apk
// ---------------------------------------------------------------------------
// 为什么不能只改 AGP 的 outputFileName：Flutter 的 gradle 插件会在 assemble 任务的
// doLast 里把 AGP 产物复制成固定名字（app[-abi]-<mode>.apk），而 Dart 侧的
// `flutter build apk` 也按这个名字找产物——找不到会直接报
// "Expected ...app-release.apk, file not found"。所以这里保留原名不动，
// **额外复制一份人类可读的名字**（复制而非改名，Flutter 的构建链不受影响）。
//
// 版本号取 `defaultConfig.versionName`，它等于 pubspec.yaml 的 `version` 主版本段
// （由 Flutter 注入），发版只改 pubspec 一处即可。
val appDisplayName = "QustSchedule"

afterEvaluate {
    val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk")
    val apkNamePattern =
        Regex("^app(?:-([A-Za-z0-9_-]+))?-(debug|profile|release)\\.apk$")

    listOf("assembleDebug", "assembleProfile", "assembleRelease").forEach { taskName ->
        tasks.matching { it.name == taskName }.configureEach {
            doLast {
                val dir = flutterApkDir.get().asFile
                if (!dir.isDirectory) return@doLast
                val version = android.defaultConfig.versionName ?: "unknown"
                // 先清掉上一次构建留下的带版本号的副本，避免目录里堆一堆旧版本。
                dir.listFiles()
                    ?.filter { it.isFile && it.name.startsWith("${appDisplayName}_v") }
                    ?.forEach { it.delete() }
                dir.listFiles()
                    ?.filter { it.isFile }
                    ?.forEach { apk ->
                        val match = apkNamePattern.find(apk.name) ?: return@forEach
                        val abi = match.groupValues[1]
                        val mode = match.groupValues[2]
                        val suffix = listOfNotNull(
                            abi.takeIf { it.isNotEmpty() },
                            mode.takeIf { it != "release" },
                        ).joinToString("-")
                        val target = File(
                            dir,
                            "${appDisplayName}_v${version}" +
                                (if (suffix.isEmpty()) "" else "-$suffix") +
                                ".apk",
                        )
                        apk.copyTo(target, overwrite = true)
                        logger.lifecycle("APK 副本：${target.name}")
                    }
            }
        }
    }
}
