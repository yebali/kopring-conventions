package x

data class FooProperties(
    val retentionDays: Int = 365, // HIT CFG-15
    val host: String,
)
