# Flutter 引擎与第三方插件（jni / jni_flutter / tink 等）大多已内置 consumer-rules，
# 这里主要保留本应用自有的包与调试排错可读类名。
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# 保留本应用包名与方法渠道类成员（BroadcastReceiver / Service / Activity 已由 AAPT2 规则保留）
-keep class com.fangzi.qustschedule.MainActivity { *; }
-keep class com.fangzi.qustschedule.reminder.** { *; }
-keep class com.fangzi.qustschedule.updater.** { *; }
