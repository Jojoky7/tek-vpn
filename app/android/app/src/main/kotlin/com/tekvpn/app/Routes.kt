package com.tekvpn.app

/**
 * IPv4 routes that send the whole internet into the VPN but leave the
 * local network (router, printer, TV) alone: 0.0.0.0/0 minus private and
 * special ranges, as the smallest list of CIDR blocks.
 */
object Routes {
    data class Cidr(val address: String, val prefix: Int)

    private val excluded = listOf(
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
        "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4",
    )

    private fun parse(cidr: String): LongRange {
        val (ip, bits) = cidr.split("/")
        val start = ip.split(".").fold(0L) { acc, part -> (acc shl 8) or part.toLong() }
        val size = 1L shl (32 - bits.toInt())
        return start until start + size
    }

    private fun format(v: Long) = "${(v shr 24) and 255}.${(v shr 16) and 255}.${(v shr 8) and 255}.${v and 255}"

    fun publicIPv4(): List<Cidr> {
        val holes = excluded.map(::parse).sortedBy { it.first }
        val out = mutableListOf<Cidr>()
        var cursor = 0L
        val end = 1L shl 32
        for (hole in holes + listOf(end until end)) {
            if (hole.first > cursor) addRange(cursor, hole.first - 1, out)
            cursor = maxOf(cursor, hole.last + 1)
        }
        return out
    }

    private fun addRange(from: Long, to: Long, out: MutableList<Cidr>) {
        var start = from
        while (start <= to) {
            var size = 32
            while (size > 0) {
                val block = 1L shl (32 - (size - 1))
                if (start % block != 0L || start + block - 1 > to) break
                size--
            }
            out += Cidr(format(start), size)
            start += 1L shl (32 - size)
        }
    }
}
