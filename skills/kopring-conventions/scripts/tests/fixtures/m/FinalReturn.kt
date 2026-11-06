package x

class FinalReturn {
    fun total(a: Int): Int {
        val b = a + 1
        return b // HIT STY-10
    }
}
