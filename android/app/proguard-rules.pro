# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# media_kit - 保留所有原生库
-keep class com.alexmercerind.media_kit.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-dontwarn com.alexmercerind.media_kit.**

# JNI 相关
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留 Kotlin 序列化
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

# OkHttp / Retrofit (网络请求)
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# 其他常用库
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Keep R8 from stripping necessary classes
-keep class * extends java.util.ListResourceBundle { *; }
-dontwarn javax.annotation.**
