package com.amaia23.hydracam

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val channelName = "hydracamv2/launch_config"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				if (call.method == "getLaunchConfig") {
					result.success(buildLaunchConfig())
				} else {
					result.notImplemented()
				}
			}
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
	}

	private fun buildLaunchConfig(): Map<String, Any?> {
		val extras = intent?.extras ?: return emptyMap()
		val payload = mutableMapOf<String, Any?>()

		extras.getString("role")?.let { payload["role"] = it }
		extras.getString("preferredMasterIp")?.let {
			payload["preferredMasterIp"] = it
		}
		if (extras.containsKey("forceSlaveMode")) {
			payload["forceSlaveMode"] = extras.getBoolean("forceSlaveMode")
		}

		return payload
	}
}
