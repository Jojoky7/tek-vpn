package com.tekvpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.service.quicksettings.TileService
import android.content.ComponentName
import com.tekvpn.tekcore.Tekcore
import java.util.concurrent.Executors

/**
 * The VPN itself: Android's virtual network card, with Xray reading it in
 * the same process. Tek's own app is left out of the VPN, so Xray's
 * connections to the servers go straight to the network instead of looping
 * back into the tunnel.
 */
class TekVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.tekvpn.app.START"
        const val ACTION_STOP = "com.tekvpn.app.STOP"
        private const val CHANNEL = "tek_vpn"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            val intent = Intent(context, TekVpnService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, TekVpnService::class.java).setAction(ACTION_STOP))
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            worker.execute { stopVpn(null) }
            return START_NOT_STICKY
        }
        // ACTION_START from the app or the tile; no action or
        // android.net.VpnService when the system brings the VPN back.
        val config = VpnConfig.load(this)
        showNotification(config?.serverName ?: "", connected = false)
        if (config == null) {
            worker.execute { stopVpn("no saved connection") }
            return START_NOT_STICKY
        }
        worker.execute { startVpn(config) }
        return START_STICKY
    }

    private fun startVpn(c: VpnConfig) {
        VpnStatus.set("starting", serverId = c.serverId, serverName = c.serverName)
        var fresh: ParcelFileDescriptor? = null
        try {
            val b = Builder()
                .setSession("Tek")
                .setMtu(c.mtu)
                .addAddress(c.address, 30)
                .addDnsServer(c.dns)
                .addRoute(c.address.substringBeforeLast('.') + ".0", 30)
            for (r in Routes.publicIPv4()) b.addRoute(r.address, r.prefix)
            // Public IPv6 goes into the tunnel too, where Xray closes it at
            // once, so apps use IPv4 instead of leaking past the VPN.
            b.addAddress("fdfe:dcba:9876::1", 126)
            b.addRoute("2000::", 3)

            val own = packageName
            val apps = c.packages.filter { it != own }
            if (c.perAppMode == "only" && apps.isNotEmpty()) {
                for (p in apps) {
                    try { b.addAllowedApplication(p) } catch (_: PackageManager.NameNotFoundException) {}
                }
            } else {
                b.addDisallowedApplication(own)
                if (c.perAppMode == "except") {
                    for (p in apps) {
                        try { b.addDisallowedApplication(p) } catch (_: PackageManager.NameNotFoundException) {}
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= 29) b.setMetered(false)
            b.setConfigureIntent(openAppIntent())

            fresh = b.establish() ?: throw IllegalStateException("VPN permission was taken away")
            Tekcore.start(c.config, fresh.fd.toLong(), c.assetDir)
            val old = tun
            tun = fresh
            fresh = null
            old?.close()
            VpnStatus.set("running", serverId = c.serverId, serverName = c.serverName)
            showNotification(c.serverName, connected = true)
            Tekcore.log("info", "VPN up: ${c.serverName}")
        } catch (e: Throwable) {
            try { fresh?.close() } catch (_: Throwable) {}
            Tekcore.log("error", "VPN start failed: ${e.message}")
            stopVpn(e.message ?: e.javaClass.simpleName)
        } finally {
            requestTileUpdate()
        }
    }

    private fun stopVpn(error: String?) {
        if (VpnStatus.state != "stopped") VpnStatus.set("stopping", error)
        try { Tekcore.stop() } catch (_: Throwable) {}
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        VpnStatus.set("stopped", error)
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
        requestTileUpdate()
    }

    override fun onRevoke() {
        // Another VPN app took over, or the user turned Tek off in the settings.
        worker.execute { stopVpn("revoked") }
    }

    override fun onDestroy() {
        if (tun != null) worker.execute { stopVpn(null) }
        worker.shutdown()
        super.onDestroy()
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun showNotification(server: String, connected: Boolean) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, TekVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = getString(if (connected) R.string.connected else R.string.connecting)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_tek)
            .setContentTitle(title)
            .setContentText(server)
            .setOngoing(true)
            .setShowWhen(connected)
            .setWhen(System.currentTimeMillis())
            .setContentIntent(openAppIntent())
            .addAction(Notification.Action.Builder(null, getString(R.string.disconnect), stop).build())
            .setColor(0xFF2F80ED.toInt())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun requestTileUpdate() {
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                TileService.requestListeningState(this, ComponentName(this, TekTileService::class.java))
            } catch (_: Throwable) {}
        }
    }
}
