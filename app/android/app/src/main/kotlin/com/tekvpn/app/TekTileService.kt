package com.tekvpn.app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** The Tek button in the quick settings: on and off with the last server. */
class TekTileService : TileService() {
    private val listener: () -> Unit = { refresh() }

    override fun onStartListening() {
        VpnStatus.addListener(listener)
        refresh()
    }

    override fun onStopListening() {
        VpnStatus.removeListener(listener)
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val on = VpnStatus.state == "running" || VpnStatus.state == "starting"
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Tek"
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = if (on) VpnStatus.serverName ?: "" else ""
        tile.updateTile()
    }

    override fun onClick() {
        if (VpnStatus.state == "running" || VpnStatus.state == "starting") {
            TekVpnService.stop(this)
            return
        }
        // Without the VPN permission or a saved server, open the app.
        if (VpnService.prepare(this) != null || VpnConfig.load(this) == null) {
            openApp()
            return
        }
        try {
            TekVpnService.start(this)
        } catch (_: Throwable) {
            openApp()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
