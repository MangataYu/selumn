package com.aerieyarrowy.selume.chatgptprobe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cryptoChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cryptoChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "selume.chatgpt_probe/crypto",
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
