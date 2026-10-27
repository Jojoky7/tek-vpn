package com.tekvpn.app

import android.os.Handler
import android.os.Looper
import com.tekvpn.tekcore.Tekcore
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArrayList

/** Where the VPN is, shared by the service, the screen and the tile. */
object VpnStatus {
    @Volatile var state: String = "stopped"
        private set
    @Volatile var since: Long = 0
        private set
    @Volatile var error: String? = null
        private set
    @Volatile var serverId: String? = null
        private set
    @Volatile var serverName: String? = null
        private set

    private val listeners = CopyOnWriteArrayList<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    val running: Boolean get() = state == "running"

    fun set(newState: String, error: String? = null, serverId: String? = this.serverId,
            serverName: String? = this.serverName) {
        if (newState == "running" && state != "running") since = System.currentTimeMillis()
        if (newState == "stopped") since = 0
        state = newState
        this.error = error
        this.serverId = serverId
        this.serverName = serverName
        main.post { listeners.forEach { it() } }
    }

    fun addListener(l: () -> Unit) = listeners.add(l)
    fun removeListener(l: () -> Unit) = listeners.remove(l)

    fun snapshot(): Map<String, Any?> {
        var up = 0L
        var down = 0L
        if (running) {
            try {
                val t = JSONObject(Tekcore.traffic())
                up = t.optLong("up")
                down = t.optLong("down")
            } catch (_: Throwable) {
            }
        }
        return mapOf(
            "state" to state,
            "since" to since,
            "error" to error,
            "serverId" to serverId,
            "up" to up,
            "down" to down,
        )
    }
}
