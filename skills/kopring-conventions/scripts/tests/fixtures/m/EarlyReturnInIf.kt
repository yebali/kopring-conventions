package x

class EarlyReturnInIf {
    fun score(a: Int): Int {
        if (a > 0) {
            val doubled = a * 2
            return doubled
        }

        return 0
    }
}
