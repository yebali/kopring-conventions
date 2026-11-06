package x

class MultiLineReturn {
    fun pair(a: Int): List<Int> {
        val b = a + 1

        return listOf(
            a,
            b,
        )
    }
}
