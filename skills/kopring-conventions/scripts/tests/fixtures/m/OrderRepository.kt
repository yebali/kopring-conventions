package x

interface OrderRepository {
    fun getByCode(code: String): String? // HIT REP-8

    fun getReferenceById(id: Long): String

    fun findByCode(code: String): String?

    fun findAllByStatus(status: String): List<String> // HIT REP-44
}
