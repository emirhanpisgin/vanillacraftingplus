package vcp

class McVersion private constructor(private val parts: List<Int>) : Comparable<McVersion> {
    override fun compareTo(other: McVersion): Int {
        val length = maxOf(parts.size, other.parts.size)
        for (i in 0 until length) {
            val left = parts.getOrElse(i) { 0 }
            val right = other.parts.getOrElse(i) { 0 }
            if (left != right) return left - right
        }
        return 0
    }

    fun atLeast(vararg version: Int): Boolean = compareTo(McVersion(version.toList())) >= 0

    companion object {
        fun parse(value: String): McVersion = McVersion(value.trim().split('.').map { it.toInt() })
    }
}
