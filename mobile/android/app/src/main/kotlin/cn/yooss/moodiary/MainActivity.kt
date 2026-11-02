package cn.yooss.moodiary

import android.media.MediaCodecList
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var cryptoChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Flutter's HiSilicon ImageReader workaround only covers API <= 29.
        // Set this before the engine initializes its renderer.
        if (Build.VERSION.SDK_INT > 29 && hasHiSiliconAvcDecoder) {
            FlutterRenderer.debugForceSurfaceProducerGlTextures = true
        }
        super.onCreate(savedInstanceState)
    }

    private val hasHiSiliconAvcDecoder: Boolean by lazy {
        runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                !codec.isEncoder && codec.name.contains("hisi", ignoreCase = true) &&
                    codec.supportedTypes.any { it.equals("video/avc", ignoreCase = true) }
            }
        }.getOrElse { error ->
            Log.w("MainActivity", "Could not inspect video decoders", error)
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cryptoChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "selume.chatgpt/crypto",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "verifyRs256") {
                    result.notImplemented()
                } else {
                    val arguments = call.arguments as? Map<*, *>
                    result.success(
                        Rs256Verifier.verify(
                            n = arguments?.get("n") as? String ?: "",
                            e = arguments?.get("e") as? String ?: "",
                            input = arguments?.get("input") as? String ?: "",
                            signature = arguments?.get("signature") as? String ?: "",
                        ),
                    )
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        cryptoChannel?.setMethodCallHandler(null)
        cryptoChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
