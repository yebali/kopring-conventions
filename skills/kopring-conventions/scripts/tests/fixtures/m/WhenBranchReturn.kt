package x

class WhenBranchReturn {
    fun label(a: Int): String {
        when (a) {
            1 -> {
                val one = "one"
                return one
            }
            else -> {}
        }

        return "other"
    }
}
