package x

class KoreanMessage {
    fun check(x: Int) {
        require(x > 0) { "양수여야 한다" } // HIT SVC-13
        check(x < 10) { "must be below 10" }
    }
}
