package io.github.haditag7.iptv_player

import android.app.ActivityManager
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecList
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter and answers `app/device` → `getCaps` with the device facts the
 * Dart side uses to pick the TV/phone shell, Lite mode and player engines.
 * Every field is read independently, so one failing API never hides the rest.
 */
class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // MediaCodecList can take a while on cheap boxes; keep it off the UI thread.
                    "getCaps" ->
                        Thread {
                            val caps = readCaps()
                            mainHandler.post { result.success(caps) }
                        }.start()
                    else -> result.notImplemented()
                }
            }
    }

    private fun readCaps(): Map<String, Any?> {
        val pm = applicationContext.packageManager
        val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memory = safe(null) { ActivityManager.MemoryInfo().also { am?.getMemoryInfo(it) } }
        return mapOf(
            "uiModeTv" to safe(false) {
                val ui = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
                ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
            },
            "leanback" to safe(false) { pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) },
            "fireTv" to safe(false) { pm.hasSystemFeature(FEATURE_FIRE_TV) },
            "touch" to safe(false) { pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) },
            "totalRamMb" to safe(0) { ((memory?.totalMem ?: 0L) / (1024L * 1024L)).toInt() },
            "isLowRamDevice" to safe(false) { am?.isLowRamDevice ?: false },
            "cpuCount" to safe(0) { Runtime.getRuntime().availableProcessors() },
            "hardware" to safe("") { Build.HARDWARE ?: "" },
            "socManufacturer" to safe(null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else null
            },
            "supportedAbis" to safe(emptyList()) { Build.SUPPORTED_ABIS.toList() },
            "decoders" to readDecoders(),
            "sdkInt" to safe(0) { Build.VERSION.SDK_INT },
            "model" to safe("") { Build.MODEL ?: "" },
            "manufacturer" to safe("") { Build.MANUFACTURER ?: "" },
        )
    }

    /** Whether a non-encoder codec claims each MIME type in [DECODER_MIMES]. */
    private fun readDecoders(): Map<String, Boolean> {
        val types: Set<String> =
            safe(emptySet()) {
                MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                    .filter { !it.isEncoder }
                    .flatMap { info -> safe(emptyList()) { info.supportedTypes.toList() } }
                    .map { it.lowercase() }
                    .toSet()
            }
        return DECODER_MIMES.associateWith { types.contains(it.lowercase()) }
    }

    private inline fun <T> safe(fallback: T, block: () -> T): T =
        try {
            block()
        } catch (error: Throwable) {
            fallback
        }

    private companion object {
        const val CHANNEL = "app/device"
        const val FEATURE_FIRE_TV = "amazon.hardware.fire_tv"
        val DECODER_MIMES =
            listOf(
                "audio/ac3",
                "audio/eac3",
                "audio/vnd.dts",
                "audio/mpeg-L2",
                "video/hevc",
                "video/mpeg2",
            )
    }
}
