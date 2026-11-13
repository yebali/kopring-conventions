# Service — Worked Examples

Rule text and exceptions live in [service.md](../service.md) and [transactions.md](../transactions.md); each heading names the rule IDs it illustrates. The KDoc summaries of [STY-16](../code-style.md#5-comments-and-kdoc) are left out so the rule shown stays in focus; production code carries them.

## SVC-9 — Validation method naming

```kotlin
private fun checkNotCanceled(order: Order) { if (order.status == Order.Status.CANCELED) throw OrderAlreadyCanceledException(order.id) }
fun verifyResetToken(token: UUID): VerifyResetTokenResult = VerifyResetTokenResult(isValid = repo.findByIdOrNull(token) != null)
fun canCancel(memberId: UUID, orderId: UUID): Boolean = ...
// ❌ validate* prefix forbidden
private fun validateNotCanceled(order: Order) { ... }
```

## SVC-10 · SVC-11 — Structural checks and every missing id

Canonical "reject unknown ids" idiom — collect **all** missing ids, then throw the domain's named exception:

```kotlin
// ✅ structural check stays in the Command, through requireValid (SVC-15)
data class CreateOrderCommand(val productIds: List<UUID>) {
    init { requireValid(productIds.isNotEmpty()) { "productIds must not be empty" } }
}
// ✅ business check is a private Service check* (in ProductService — its own domain's exception, SVC-14)
private fun checkProductsExist(ids: List<UUID>) {
    val missing = ids - productRepository.findAllById(ids).map { it.id }.toSet()
    if (missing.isNotEmpty()) throw ProductNotFoundException(missing)
}
// ❌ throws on the first miss — the client learns one bad id per round trip
ids.firstOrNull { it !in found }?.let { throw ProductNotFoundException(it) }
```

## SVC-14 · SVC-15 — Exception declaration

```kotlin
// ✅ named domain subclass + domain ErrorCode
class OrderNotFoundException(orderId: UUID, cause: Throwable? = null) : EntityNotFoundException(
    errorCode = ErrorCode.ORDER_NOT_FOUND,
    message = "Order not found: orderId=$orderId",
    cause = cause,
)
// ✅ ErrorCode entries are domain-prefixed
ORDER_NOT_FOUND("ORDER-1000", HttpStatus.NOT_FOUND.value(), "Order not found"),
ORDER_ALREADY_CANCELED("ORDER-1001", HttpStatus.CONFLICT.value(), "Order is already canceled"),

// ✅ a Command's structural check — the shared function, one shared code
requireValid(quantity > 0) { "quantity must be positive" }

// ❌ SVC-15
throw IllegalArgumentException("invalid id")
throw BusinessException(CommonErrorCode.UNEXPECTED, "...")
require(quantity > 0) { "quantity must be positive" }   // stdlib require — IllegalArgumentException is not a client error
// ❌ generic code shared across domains (hypothetical entry — the number is a placeholder)
ENTITY_NOT_FOUND("COMMON-XXXX", HttpStatus.NOT_FOUND.value(), "Entity not found"),
```

## SVC-2 · SVC-17 — Cross-domain entity-returning method

Domain B exposes an entity-returning method, and domain A calls it instead of injecting B's Repository directly.

```kotlin
// ✅ the member domain exposes the entity-returning method for cross-domain use
@Service
@Transactional
class MemberService(private val memberRepository: MemberRepository) : Logger() {
    @Transactional(readOnly = true)
    fun getEntity(id: UUID): Member =
        memberRepository.findByIdOrNull(id)?.takeUnless { it.isDeleted } ?: throw MemberNotFoundException(id)   // findById is not filtered (REP-27)
}
// ✅ the order domain asks it instead of injecting MemberRepository, and stores only the id (REP-15)
@Service
@Transactional
class OrderService(private val memberService: MemberService, private val orderRepository: OrderRepository) {
    fun createOrder(command: CreateOrderCommand): OrderResult =
        orderRepository.save(Order(memberId = memberService.getEntity(command.memberId).id)).let(OrderResult::from)
}
```

## SVC-20 — Breaking a bean cycle without `@Lazy`

```kotlin
// ❌ Bad — @Lazy hides the cycle
class OrderService(@param:Lazy private val paymentService: PaymentService) { ... }
class PaymentService(private val orderService: OrderService) { ... }

// ✅ Good — technique (2): move the read-time decoration up to the controller
class OrderController(private val orderService: OrderService, private val paymentService: PaymentService) {
    fun getOrder(orderId: UUID, authUser: AuthUser): OrderResponse =
        OrderResponse.from(
            result = orderService.getOrder(GetOrderCommand(orderId = orderId, memberId = authUser.id)),   // knows nothing about payments
            payments = paymentService.listPayments(ListPaymentsCommand(orderId = orderId)),             // composed in the response
        )
}
class OrderService(private val orderRepository: OrderRepository, ...) { ... }   // no paymentService edge
```

## SVC-23 — Two-stage saveAll

Two-stage `saveAll` when the batch has an FK dependency:

```kotlin
// ❌ loop save — the batch reads as per-row work; JDBC batching comes from hibernate.jdbc.batch_size, order_inserts and non-IDENTITY ids, not from saveAll
command.orders.forEach { row ->
    val order = orderRepository.save(newOrder(row))
    orderItemRepository.save(OrderItem(order, ...))
}
// ✅ parent saveAll, then child saveAll
val orders = orderRepository.saveAll(command.orders.map { newOrder(it) })
orderItemRepository.saveAll(command.orders.zip(orders) { row, order -> OrderItem(order = order, ...) })
```

## SVC-27 · SVC-28 — EnumMapper

```kotlin
// Packet — shared module packet/type/ (protocol adapter only; carries the external wire code)
enum class OrderStatus(val code: Int) { PLACED(1001), CANCELLED(1002) ; @JsonValue val value = code }
// Message — shared module message/type/ (name-serialized, message broker)
// Service — {module}/.../enumerate/
enum class OrderStatus { PLACED, CANCELED }
// Entity — nested in the @Entity class
@Entity
class Order {
    @Enumerated(EnumType.STRING) val status: Status
    enum class Status { PLACED, CANCELED }
}

object OrderEnumMapper {
    fun ServiceOrderStatus.toEntityOrderStatus(): Order.Status = when (this) {   // no `else` — drift becomes a compile error
        ServiceOrderStatus.PLACED -> Order.Status.PLACED
        ServiceOrderStatus.CANCELED -> Order.Status.CANCELED
    }
}
```

## SVC-30 · SVC-31 — Service vs Component

```kotlin
// ✅ a domain use case is a *Service — class-level @Transactional, readOnly on reads (TX-1)
@Service
@Transactional
class OrderService(private val orderRepository: OrderRepository) : Logger() {
    @Transactional(readOnly = true) fun getEntity(orderId: UUID): Order = ...
}
// ✅ a flow with an outbound call is a *Facade — no @Transactional, no Repository (TX-3)
@Component
class OrderFacade(private val orderService: OrderService, private val paymentClient: PaymentClient) { ... }
// ✅ drop "Template" → "AdvisoryLock" names the lock, not the bean acquiring it, so the suffix stays
@Component
class AdvisoryLockTemplate(private val entityManager: EntityManager) { fun acquireLocks(exclusiveKeys: List<String>, sharedKeys: List<String> = emptyList()) { ... } }
// ✅ drop nothing — the bare noun already names the bean
@Component
class InvoiceGenerator(...) { fun generate(command: GenerateInvoiceCommand): GenerateInvoiceResult { ... } }
// ❌ naming an infrastructure wrapper *Service confuses it with a domain service
@Service class AdvisoryLockService(...)
```

## SVC-38 · SVC-39 · SVC-40 · SVC-41 — Cross-domain communication

The deployable `app-service` holds the `user`, `group`, `board` and `notification` domains; `auth-service` is another deployable. Creating a group needs the owner's answer (SVC-39 row 2 → inject), creates the group's default board in the same transaction (row 3 → synchronous listener) and notifies the owner after commit (row 3 → `AFTER_COMMIT` listener).

```kotlin
// group/event/GroupCreatedEvent.kt — owned by the publishing domain, named as a past fact
data class GroupCreatedEvent(val groupId: UUID, val ownerId: UUID, val name: String)

// group/service/GroupService.kt — injects UserService for an answer; knows nothing about board or notification
@Service
@Transactional
class GroupService(
    private val userService: UserService,
    private val groupRepository: GroupRepository,
    private val applicationEventPublisher: ApplicationEventPublisher,
) {
    fun createGroup(command: CreateGroupCommand): CreateGroupResult {
        val group = groupRepository.save(command.toEntity(ownerId = userService.getActiveEntity(command.ownerId).id))
        applicationEventPublisher.publishEvent(GroupCreatedEvent(groupId = group.id, ownerId = command.ownerId, name = group.name))

        return CreateGroupResult.from(group)
    }
}

// board/event/BoardEventListener.kt — the board must commit with the group → synchronous
@Component
class BoardEventListener(private val boardService: BoardService) {
    @EventListener
    fun onGroupCreated(event: GroupCreatedEvent) {
        boardService.createDefaultBoard(CreateDefaultBoardCommand(groupId = event.groupId))
    }
}

// notification/event/NotificationEventListener.kt — a lost notification can be resent → after commit, in its own transaction
@Component
class NotificationEventListener(
    private val notificationService: NotificationService,
    private val transactionRunner: TransactionRunner,
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    fun onGroupCreated(event: GroupCreatedEvent) {
        transactionRunner.inNewTx {
            notificationService.notifyGroupCreated(NotifyGroupCreatedCommand(userId = event.ownerId, groupName = event.name))
        }
    }
}
```

```kotlin
// ❌ GroupService injects BoardService and NotificationService and ignores what they return — telling, not asking
fun createGroup(command: CreateGroupCommand): CreateGroupResult {
    val group = groupRepository.save(command.toEntity(ownerId = userService.getActiveEntity(command.ownerId).id))
    boardService.createDefaultBoard(CreateDefaultBoardCommand(groupId = group.id))
    notificationService.notifyGroupCreated(NotifyGroupCreatedCommand(userId = command.ownerId, groupName = group.name))   // also runs before commit

    return CreateGroupResult.from(group)
}
```

Between deployables (SVC-38):

```kotlin
// ✅ the caller waits on a read — app-service needs the account to go on, so it reads auth-service through its HTTP client
@FeignClient(name = "auth-service", configuration = [AuthFeignConfig::class])
interface AccountClient {
    @GetMapping("/api/v1/accounts/{accountId}")
    fun getAccount(@PathVariable accountId: UUID): AccountResponse

    // ✅ the caller waits on a write — the end user receives the copied file, so the call is HTTP
    @PostMapping("/api/v1/files/copies")
    fun copyFile(@RequestBody request: CopyFileRequest): CopyFileResponse
}

// ✅ the caller does not wait — auth-service tells app-service to hand over a deleted user's groups; user/kafka/DeactivateUserMessageListener.kt consumes it
@Component
class DeactivateUserMessageListener(private val userService: UserService) {
    @KafkaListener(topics = ["\${app.kafka.topics.deactivate-user}"])
    fun onDeactivateUser(message: DeactivateUserMessage) {
        userService.deactivateUser(DeactivateUserCommand.from(message))
    }
}

// ❌ the same hand-over over HTTP, with the result discarded — it fails when app-service is down and leaves the two sides inconsistent
interface UserClient {
    @PostMapping("/api/v1/users/{userId}/deactivation")
    fun deactivateUser(@PathVariable userId: UUID)
}
```

## TX-1 · TX-5 — Transactional placement and the boundary API

```kotlin
@Service
@Transactional
class OrderService(...) : Logger() {
    @Transactional(readOnly = true) fun getOrder(command: GetOrderCommand): OrderResult = ...
    fun createOrder(command: CreateOrderCommand): OrderResult = ...                      // the class-level transaction
    @Transactional(rollbackFor = [IOException::class])
    fun importOrders(command: ImportOrdersCommand): ImportOrdersResult = ...             // a checked exception can leave it (TX-15)
}
// ❌ class-level readOnly — a write method that forgets its override loses its writes without an error (TX-17)
@Service @Transactional(readOnly = true) class OrderService(...)
// ❌ no class-level annotation — a method that forgets its own runs every repository call in a separate transaction
@Service class OrderService(...)
// ❌ a Service that calls out — the charge would run inside the transaction (TX-2)
@Service @Transactional class OrderService(private val paymentClient: PaymentClient, ...)
```

Boundary API — a bean that is not a Service opens a boundary through `TransactionRunner`:

```kotlin
// ❌ hand-rolled REQUIRES_NEW with no reason to exist
private val tx = TransactionTemplate(requireNotNull(transactionTemplate.transactionManager) { "..." })
    .apply { propagationBehavior = PROPAGATION_REQUIRES_NEW }
// ❌ readOnly hidden in a field of the raw template, around a pure read (TX-5, TX-6)
private val readTransactionTemplate = transactionTemplate.asReadOnly()
val page = readTransactionTemplate.execute { ... }
// ✅ an AFTER_COMMIT listener's write (TX-7)
transactionRunner.inNewTx { notificationService.notifyGroupCreated(command) }
// ❌ inTx inside a Service or a Facade — the Service method is the boundary (TX-1, TX-3)
```

## TX-3 · TX-4 — Facade and compensation

A flow with an external call between two DB steps, and its explicit compensation:

```kotlin
// ❌ Bad — the Service calls out: the HTTP call runs inside the transaction and holds the row lock for its whole duration
@Service
@Transactional
class OrderService(private val orderRepository: OrderRepository, private val paymentClient: PaymentClient) {
    fun placeOrder(command: PlaceOrderCommand): PlaceOrderResult {
        val order = orderRepository.save(command.toEntity())   // INSERT (lock held, before commit)
        val payment = paymentClient.charge(order.id)           // HTTP — the payment system can't touch the same row

        return PlaceOrderResult.from(order = order, payment = payment)
    }
}

// ✅ Good — the Facade lists the flow; each Service call commits on its own and the external call runs between them
@Component
class OrderFacade(private val orderService: OrderService, private val paymentClient: PaymentClient) : Logger() {
    fun placeOrder(command: PlaceOrderCommand): PlaceOrderResult {
        val order = orderService.createOrder(command.toCreateOrderCommand())      // commits as PAYMENT_PENDING, lock released
        val payment = try {
            paymentClient.charge(orderId = order.id, idempotencyKey = order.id)   // outside any transaction; the key stops a retry or reconciliation from charging twice
        } catch (e: PaymentDeclinedException) {              // definite failure — the ErrorDecoder mapped the remote 4xx (CTL-26)
            safeDeleteOrder(orderId = order.id, memberId = command.memberId)      // explicit compensation
            throw e
        }                                                    // a timeout, reset or 5xx is an unknown outcome: it propagates, and the order stays PAYMENT_PENDING for reconciliation

        return orderService.completePayment(CompletePaymentCommand(orderId = order.id, paymentId = payment.id))
            .let { PlaceOrderResult.from(order = it, payment = payment) }
    }

    private fun safeDeleteOrder(orderId: UUID, memberId: UUID) {
        runCatching { orderService.deleteOrder(DeleteOrderCommand(orderId = orderId, memberId = memberId)) }
            .onFailure { e -> logger.warn(e) { "Failed to compensate: orderId=$orderId" } }
    }
}
```

## TX-8 · TX-9 — Lock selection: advisory vs Redis

*If the project uses PostgreSQL advisory locks / Redis.*

```kotlin
// ✅ startup seeding in an initializer bean (not a Service) — mutual exclusion is needed all the way to the commit, so inTx wraps only the lock and the DB work (TX-9)
@EventListener(ApplicationReadyEvent::class)
fun init() {
    transactionRunner.inTx {
        advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
        seedCategories()
    }
}
// ✅ periodic work — if it is not acquired, the next cycle recovers
distributedLockTemplate.runIfAcquired(key = LOCK_KEY, ttl = LOCK_TTL) { staleOrderService.cancelStaleOrders() }
// ❌ advisory outside a transaction — the lock is released at once and blocks nothing (no error, no log)
@EventListener(ApplicationReadyEvent::class)
fun init() { advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY)); seedCategories() }
// ❌ a fallback that waits and then runs unlocked — it reads as if the "lock" guaranteed something it does not
fun runAwaitingLock(key: String, ...) {
    while (...) { if (runIfAcquired(...)) return }
    logger.warn { "Lock wait timed out, running unguarded" }
    block()
}
```

Narrow the boundary to lock + DB work only:

```kotlin
// ❌ work that must happen after the commit is dragged inside the transaction — and @Transactional sits on a bean that is not a Service (TX-1)
@EventListener(ApplicationReadyEvent::class)
@Transactional
fun initialize() {
    advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
    ensureDefaultCategories()
    catalogSyncExecutor.execute { syncCatalog() }   // starts in the uncommitted state
}
// ✅ boundary covers only the lock + the DB work — acquireLocks sits inside the transaction inTx opens, so the advisory requirement still holds
@EventListener(ApplicationReadyEvent::class)
fun initialize() {
    transactionRunner.inTx {
        advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
        ensureDefaultCategories()
    }
    catalogSyncExecutor.execute { syncCatalog() }   // after the commit
}
```

## TX-10 — Lock-key helper

*If the project uses PostgreSQL advisory locks.*

Key-building rule lives in one private helper; call sites name only the target:

```kotlin
// ✅ the rule lives in one place; the call site passes only the target
private fun lockCategoryPaths(vararg paths: String) = lockCategoryPaths(paths.toList())
private fun lockCategoryPaths(paths: List<String>) {
    advisoryLockTemplate.acquireLocks(
        exclusiveKeys = paths.distinct(),
        sharedKeys = paths.flatMap { it.strictAncestorPaths() }.distinct(),
    )
}
lockCategoryPaths(command.path)
lockCategoryPaths(command.sourcePath, command.targetPath)

// ❌ the same rule spelled differently at every call site — omitting distinct() causes nothing to happen
acquireLocks(
    exclusiveKeys = listOf(command.sourcePath, command.targetPath).distinct(),
    sharedKeys = (command.sourcePath.strictAncestorPaths() + command.targetPath.strictAncestorPaths()).distinct(),
)
```
