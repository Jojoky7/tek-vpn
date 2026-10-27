package com.tekvpn.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.tekvpn.tekcore.Tekcore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** The screen. Talks to the Dart side over "tek/core" and "tek/core/status". */
class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_VPN = 7001
        private const val REQUEST_NOTIFICATIONS = 7002
    }

    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var pendingStart: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "tek/core").setMethodCallHandler(::onCall)
        EventChannel(messenger, "tek/core/status").setStreamHandler(StatusStream())
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("core", e.message, null) }
            }
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(VpnStatus.snapshot())
            "start" -> start(call, result)
            "stop" -> {
                TekVpnService.stop(this)
                result.success(null)
            }
            "realPing" -> background(result) {
                Tekcore.realPing(call.argument<String>("request") ?: "{}", call.argument<String>("assetDir") ?: "")
            }
            "tcpPing" -> background(result) { Tekcore.tcpPing(call.argument<String>("request") ?: "{}") }
            "cancelPing" -> {
                Tekcore.cancelPing()
                result.success(null)
            }
            "logs" -> background(result) {
                Tekcore.logs((call.argument<Number>("since") ?: 0).toLong())
            }
            "setLogLevel" -> {
                Tekcore.setLogLevel(call.argument<String>("level") ?: "warning")
                result.success(null)
            }
            "validate" -> background(result) { Tekcore.validate(call.argument<String>("config") ?: "{}") }
            "version" -> result.success(Tekcore.version())
            "apps" -> background(result) { launcherApps() }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val config = VpnConfig(
            config = call.argument<String>("config") ?: "{}",
            assetDir = call.argument<String>("assetDir") ?: "",
            perAppMode = call.argument<String>("perAppMode") ?: "off",
            packages = call.argument<List<String>>("packages") ?: emptyList(),
            serverId = call.argument<String>("serverId") ?: "",
            serverName = call.argument<String>("serverName") ?: "",
            address = call.argument<String>("address") ?: "172.19.0.1",
            dns = call.argument<String>("dns") ?: "172.19.0.2",
            mtu = call.argument<Number>("mtu")?.toInt() ?: 1500,
        )
        try {
            VpnConfig.save(this, config)
        } catch (e: Throwable) {
            result.error("core", e.message, null)
            return
        }
        askForNotifications()
        val consent = VpnService.prepare(this)
        if (consent == null) {
            TekVpnService.start(this)
            result.success(null)
            return
        }
        pendingStart?.error("cancelled", "a newer start replaced this one", null)
        pendingStart = result
        try {
            startActivityForResult(consent, REQUEST_VPN)
        } catch (e: Throwable) {
            pendingStart = null
            result.error("permission_denied", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN) return
        val result = pendingStart ?: return
        pendingStart = null
        if (resultCode == RESULT_OK) {
            TekVpnService.start(this)
            result.success(null)
        } else {
            result.error("permission_denied", "the user did not allow the VPN", null)
        }
    }

    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    /** Apps with a launcher icon, without Tek itself. */
    private fun launcherApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val size = (40 * resources.displayMetrics.density).toInt().coerceAtLeast(48)
        return pm.queryIntentActivities(intent, 0).mapNotNull { info ->
            val pkg = info.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) return@mapNotNull null
            val icon = try {
                val d = info.loadIcon(pm)
                val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                d.setBounds(0, 0, size, size)
                d.draw(canvas)
                ByteArrayOutputStream().use { out ->
                    bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                    out.toByteArray()
                }
            } catch (_: Throwable) {
                null
            }
            mapOf("package" to pkg, "label" to info.loadLabel(pm).toString(), "icon" to icon)
        }
    }

    /** Sends the VPN state to Dart on every change and once a second while connected. */
    private inner class StatusStream : EventChannel.StreamHandler {
        private var sink: EventChannel.EventSink? = null
        private val listener: () -> Unit = { sink?.success(VpnStatus.snapshot()) }
        private val tick = object : Runnable {
            override fun run() {
                if (VpnStatus.running) sink?.success(VpnStatus.snapshot())
                main.postDelayed(this, 1000)
            }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
            VpnStatus.addListener(listener)
            events.success(VpnStatus.snapshot())
            main.postDelayed(tick, 1000)
        }

        override fun onCancel(arguments: Any?) {
            VpnStatus.removeListener(listener)
            main.removeCallbacks(tick)
            sink = null
        }
    }
}
