package x

object TextFormat {
    fun format(text: String, case: LetterCase): String = if (case == LetterCase.UPPER) text.uppercase() else text.lowercase()
}

enum class LetterCase { UPPER, LOWER }
