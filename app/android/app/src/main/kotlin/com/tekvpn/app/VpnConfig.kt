package com.tekvpn.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The last connection request, kept in the app's private storage so the
 * VPN can come back by itself: after the system restarts the service, from
 * the quick settings tile, or with Android's always-on VPN.
 */
data class VpnConfig(
    val config: String,
    val assetDir: String,
    val perAppMode: String,
    val packages: List<String>,
    val serverId: String,
    val serverName: String,
    val address: String,
    val dns: String,
    val mtu: Int,
) {
    fun toJson(): String = JSONObject()
        .put("config", config)
        .put("assetDir", assetDir)
        .put("perAppMode", perAppMode)
        .put("packages", JSONArray(packages))
        .put("serverId", serverId)
        .put("serverName", serverName)
        .put("address", address)
        .put("dns", dns)
        .put("mtu", mtu)
        .toString()

    companion object {
        private fun file(context: Context) = File(context.filesDir, "vpn/last.json")

        fun save(context: Context, c: VpnConfig) {
            val f = file(context)
            f.parentFile?.mkdirs()
            val tmp = File(f.path + ".tmp")
            tmp.writeText(c.toJson())
            tmp.renameTo(f)
        }

        fun load(context: Context): VpnConfig? = try {
            val j = JSONObject(file(context).readText())
            val pk = j.optJSONArray("packages") ?: JSONArray()
            VpnConfig(
                config = j.getString("config"),
                assetDir = j.optString("assetDir"),
                perAppMode = j.optString("perAppMode", "off"),
                packages = List(pk.length()) { pk.getString(it) },
                serverId = j.optString("serverId"),
                serverName = j.optString("serverName"),
                address = j.optString("address", "172.19.0.1"),
                dns = j.optString("dns", "172.19.0.2"),
                mtu = j.optInt("mtu", 1500),
            )
        } catch (_: Throwable) {
            null
        }
    }
}
