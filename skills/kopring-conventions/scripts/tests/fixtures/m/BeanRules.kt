package x

import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Duration
import java.util.Optional
import java.util.concurrent.atomic.AtomicBoolean

@Service
@Transactional
class BeanRules(private val repository: BeanRepository) {
    private val failing = AtomicBoolean(false)
    private var lastSeen = 0L // HIT STY-59
    private val seen = mutableMapOf<Long, String>() // HIT STY-59

    private lateinit var consumer: AutoCloseable

    @Volatile
    private var ready = false

    @Transactional
    fun rename(id: Long) = touch(id)

    @Transactional
    private fun touch(id: Long) = repository.findByIdOrNull(id) // HIT TX-18

    @Transactional(
        readOnly = true,
    )
    private fun peek(id: Long) = repository.findByIdOrNull(id) // HIT TX-18

    fun validateName(name: String) = name.isNotBlank() // HIT SVC-9

    fun checkName(name: String) = name.isNotBlank()

    fun one(id: Long): Optional<String> = repository.findById(id) // HIT REP-42

    fun log(command: String, requestId: String) {
        logger.info { "Order created: command=$command" } // HIT STY-36
        logger.info { "Order created: requestId=$requestId, length=${command.length}" }
    }

    companion object {
        val TTL: Duration = Duration.ofSeconds(30)
    }
}
