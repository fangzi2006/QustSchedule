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
    compileSdk = flutter.compileSdkVersion
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
        // 调试包与正式包签名彻底分离：
        // debug 固定使用调试证书，避免可被调试的测试包借用正式证书或误覆盖正式版；
        // 需要不掉登录态覆盖测试时，直接构建 release 包安装即可。
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // 有 key.properties 就用正式发布签名；没有就退回 debug 签名
            // （本地可正常出包，但无法覆盖正式密钥签出的版本）。
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // 开启原生 .so 动态库 Deflate 压缩（针对直发 APK 场景将 ~18.8 MB 的 Flutter/App SO 库
    // 压缩后再打包，显著减小下载体积；代价是安装时需在手机本地解压一份动态库）。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 流体云走公开 API：NotificationCompat.ProgressStyle / setRequestPromotedOngoing /
    // setShortCriticalText 都在 androidx.core 1.17 才齐；不接 OPPO 幼苗 SDK 与 UPK。
    implementation("androidx.core:core-ktx:1.17.0")
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
