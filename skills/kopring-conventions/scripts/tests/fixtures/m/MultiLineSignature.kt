package x

class MultiLineSignature {
    fun sum(
        a: Int,
        b: Int,
    ): Int {
        val c = a + b
        return c // HIT STY-10
    }
}
