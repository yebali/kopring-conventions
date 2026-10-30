# Repository — Worked Examples

Rule text, conditions and exceptions live in [repository.md](../repository.md); this file only illustrates them.

## REP-1 · REP-2 — Query construction

```kotlin
// ✅ derived query — a single one-segment field
interface OrderItemRepository : JpaRepository<OrderItem, UUID>, CustomOrderItemRepository {
    fun findAllByOrder(order: Order): List<OrderItem>
}

// ✅ QueryDSL Custom Repository with a subquery — the only way to write bulk DML
class CustomOrderItemRepositoryImpl(
    private val queryFactory: JPAQueryFactory,
) : CustomOrderItemRepository {
    override fun deleteAllByMember(member: Member) {
        val orderIdsOfMember = JPAExpressions
            .select(order.id).from(order).where(order.member.id.eq(member.id))
        queryFactory.delete(orderItem)
            .where(orderItem.order.id.`in`(orderIdsOfMember))
            .execute()
    }
}

// ❌ @Query in any form — native, JPQL, UPDATE/DELETE, or a "simple" SELECT
@Modifying
@Query(value = "DELETE FROM order_item WHERE order_id = :orderId", nativeQuery = true)
fun deleteAllByOrderId(@Param("orderId") orderId: UUID)

@Query("SELECT oi FROM OrderItem oi WHERE oi.order = :order AND oi.order.deletedAt IS NULL")
fun findAllByOrder(order: Order): List<OrderItem>
// → a QueryDSL method on CustomOrderItemRepository (two conditions are not a derived query, REP-2)
```

## REP-5 — `by()` predicate extraction

```kotlin
// ✅ by(query) called inline at each use site — reused by the content query and the count query
override fun pageByQuery(query: PageOrderQuery): Page<Order> {
    val content = queryFactory.selectFrom(order).where(by(query)).fetch()
    // ...
}

private fun by(query: PageOrderQuery): BooleanBuilder =
    BooleanBuilder(order.deletedAt.isNull)
        .and(order.member.id.eq(query.memberId))
        .and(query.startOrderedAt?.let { order.orderedAt.goe(it) })
        .and(query.keyword?.takeIf { it.isNotBlank() }?.let(::buildKeywordPredicate))

// ❌ BooleanBuilder assembled inline, imperatively, inside pageByQuery()
override fun pageByQuery(query: PageOrderQuery): Page<Order> {
    val where = BooleanBuilder().and(order.deletedAt.isNull)
    query.startOrderedAt?.let { where.and(order.orderedAt.goe(it)) }
    // ...
}

// ❌ hoisting the call — val where = by(query)  (single-use intermediate, STY-19)
```

## REP-6 — Q-class import and self-join alias

```kotlin
// ✅ default kapt singleton imported directly
import com.example.shop.order.entity.QOrder.order

queryFactory.selectFrom(order).where(order.id.eq(id).and(order.deletedAt.isNull)).fetchOne()

// ❌ local underscore alias field
companion object { private val order_ = QOrder("order_") }

// ✅ self-join needs a second alias — name it meaningfully
val parentCategory = QCategory("parentCategory")
queryFactory.selectFrom(category).leftJoin(category.parent, parentCategory).fetch()
// ❌ val category_ = QCategory("category_")   — formal suffix carries no meaning

// ✅ reserved-word entity name → QueryDSL emits `keyword$`; hide the `$` with a rename import
import com.example.shop.x.entity.`QKeyword$`.`keyword$` as keyword
```

## REP-5 — Query skeleton stays inline

```kotlin
// ✅ the whole selectFrom…join…where…fetch chain is visible in the method.
//    by() and withPagination() are chainable and read inline; the id tie-breaker ends the ordering (REP-12).
override fun pageByQuery(query: PageOrderQuery): Page<Order> {
    val content = queryFactory
        .selectFrom(order)
        .innerJoin(order.member, member).fetchJoin()
        .leftJoin(order.payment, payment).fetchJoin()
        .where(by(query))
        .withPagination(query.pageable, *orderTransformer.transform(query.pageable.sort), order.id.asc())
        .fetch()

    return PageableExecutionUtils.getPage(content, query.pageable) {
        queryFactory.select(order.count())
            .from(order)
            .innerJoin(order.member, member)
            .where(by(query))
            .fetchOne() ?: 0L
    }
}

// ❌ skeleton hidden behind a generic helper — the call site no longer shows which joins run
override fun pageByQuery(query: PageOrderQuery): Page<Order> {
    val content = queryFactory.selectFrom(order)./* join */.where(by(query))
    return pageOf(content, query.pageable, orderTransformer) { /* count query */ }
}
```

## REP-9 — Query-object clustering

```kotlin
// ✅ conditions encapsulated in a Query object, one existsByQuery method
data class ExistsOrderItemQuery(
    val product: Product,
    val orderPaid: Boolean? = null,      // null = not filtered
    val orderDeleted: Boolean? = null,
)

interface CustomOrderItemRepository {
    fun existsByQuery(query: ExistsOrderItemQuery): Boolean
}

// call site — named arguments carry the intent
orderItemRepository.existsByQuery(
    ExistsOrderItemQuery(product = product, orderPaid = true, orderDeleted = false),
)

// ❌ conditions baked into method names — a new condition forks yet another method
fun existsByProductIdAndOrderDeletedAtIsNullAndOrderPaidAtIsNotNull(...)
fun existsByProductIdInAndOrderDeletedAtIsNullAndOrderPaidAtIsNotNull(...)
```

```kotlin
// ✅ canonical shape: list + exists share one filter axis and one by();
//    page has its own axis (period · explicit id list) and its own by()
data class OrderFilter(val status: OrderStatus? = null, val paymentMethod: PaymentMethod? = null, val shipped: Boolean? = null)
data class ListOrderQuery(val memberIds: List<UUID>? = null, val filter: OrderFilter = OrderFilter())
data class PageOrderQuery(val startOrderedAt: ZonedDateTime? = null, val endOrderedAt: ZonedDateTime? = null, val orderIds: List<UUID>? = null, val pageable: Pageable)

interface CustomOrderRepository {
    fun listByQuery(query: ListOrderQuery): List<Order>       // by(ListOrderQuery) — shared with exists
    fun existsByQuery(query: ListOrderQuery): Boolean         // same by(), method kept separate
    fun pageByQuery(query: PageOrderQuery): Page<Order>       // own axis, own by(PageOrderQuery)
}

// ❌ condition-only variants fragmenting into many methods
fun findAllByOrderId(orderId: UUID): List<OrderItem>
fun findAllByOrderIdAndStatus(orderId: UUID, status: OrderItemStatus): List<OrderItem>
// → fun listByQuery(query: ListOrderItemQuery): List<OrderItem>   // ListOrderItemQuery(order, status? = null)
```

```kotlin
// fetch-graph variants and the paged read are both declared on the Custom interface
// and implemented as a single QueryDSL fetch-join — not @EntityGraph + a second query.
interface OrderRepository : JpaRepository<Order, UUID>, CustomOrderRepository

interface CustomOrderRepository {
    fun findByIdWithItems(id: UUID): Order?
    fun pageByQuery(query: PageOrderQuery): Page<Order>
}
```

## REP-14 — Entity `@Column` policy

```kotlin
// ✅ let inference do the rest; annotate only special types / non-default length / constraints
@Entity
class Product(
    @Enumerated(EnumType.STRING) val status: ProductStatus,  // name auto, NOT NULL owned by the migration (REP-16)
    val createdBy: UUID,                                     // no annotation
    @Column(unique = true, length = 32) val code: String,
    var name: String,                                        // length default 255
    @Column(length = 64) var sku: String? = null,
    @Column(columnDefinition = "text") var description: String? = null,
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    val attributes: Map<String, Any> = emptyMap(),           // JSONB needs both (REP-22)
)

// ❌ re-declaring what Hibernate already infers
@Entity
class Product(
    @Column(name = "status", nullable = false, length = 32) val status: ProductStatus,
    @Column(name = "created_by", nullable = false) val createdBy: UUID,
    @Column(name = "name", length = 255) var name: String,
)
```

```kotlin
// ✅ @MapsId — the association's @JoinColumn already names the PK column
@MapsId @OneToOne(fetch = FetchType.LAZY) @JoinColumn(name = "payment_id")
val payment: Payment,
…
@Id val id: UUID? = null
// ❌ @Id @Column(name = "payment_id") val id: UUID? = null
```

## REP-22 · REP-23 · REP-24 — JSONB

*If the project uses PostgreSQL JSONB.*

```kotlin
// ✅ mapping — both annotations, always (REP-22)
@JdbcTypeCode(SqlTypes.JSON)
@Column(columnDefinition = "jsonb")
val metadata: Map<String, Any> = emptyMap()   // Order.metadata

// ✅ query via the shared JSONB util (REP-23)
queryFactory.selectFrom(order).where(order.metadata.jsonbField("channel").eq("mobile")).fetch()
```

The default shape of the shared JSONB util; a project may already have its own equivalent — use that:

```kotlin
fun MapPath<*, *, *>.jsonbField(vararg keys: String): StringTemplate {
    require(keys.isNotEmpty()) { "At least one key must be provided" }

    val placeholders = (0..keys.size).joinToString(separator = ", ") { "{$it}" }

    return Expressions.stringTemplate(
        "CAST(jsonb_extract_path_text($placeholders) AS text)", // 명시적 text 캐스팅이라야 Hibernate 타입 검사를 통과한다
        listOf(this) + keys.map { Expressions.constant(it) },
    )
}
```

```kotlin
// ✅ insert-only entity + nested-collection JSONB → @Immutable kills the phantom UPDATE (REP-24)
@Entity
@Immutable
class OrderHistory(
    @ManyToOne(fetch = FetchType.LAZY) val order: Order,
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    val snapshot: Map<String, Any> = emptyMap(),   // {"items": [{"sku": "A-1", "quantity": 2}]}
)
// ❌ @Immutable on an entity that has an update path (Order itself) — UPDATEs are silently ignored
```

```kotlin
// ✅ JSONB sort — text order only, no type cast (REP-23)
val orderSpecifiers = OrderSpecifierTransformer(order)
    .transform(pageable.sort)   // "metadata.priority" → ORDER BY jsonb_extract_path_text(metadata, 'priority') (text)
```

## REP-27 · REP-28 — Soft delete shape

```kotlin
// ✅ the fixed three pieces — column + isDeleted getter + delete() transition
var deletedAt: ZonedDateTime? = null
    protected set

val isDeleted: Boolean
    get() = deletedAt != null

fun delete() {
    deletedAt = ZonedDateTime.now()
    logger.info { "Order deleted: id=$id, deletedAt=$deletedAt" }   // STY-34 — assigned field only
}
```

```kotlin
// ✅ single/list read — deletedAt.isNull stated in the where clause
.where(order.id.eq(id).and(order.deletedAt.isNull))

// ✅ paged read — seed the by() builder with it
private fun by(query: PageOrderQuery): BooleanBuilder =
    BooleanBuilder(order.deletedAt.isNull)
        .and(query.startOrderedAt?.let { order.orderedAt.goe(it) })

// ❌ @SQLRestriction / @SQLDelete / @Where — never introduce one
```

```sql
-- ✅ unique column on a soft-delete entity → partial unique index (REP-28)
CREATE UNIQUE INDEX uq_product_code
    ON product (code)
    WHERE code IS NOT NULL AND deleted_at IS NULL;
```

## REP-30 — Bulk delete mixing

```kotlin
// ❌ JPQL bulk delete mixed with entity delete → TransientObjectException, session inconsistency
orderItemRepository.deleteAllByOrderId(order.id)   // QueryDSL bulk delete in CustomOrderItemRepositoryImpl
orderRepository.delete(order)

// ✅ both sides through JPA entity delete
orderItemRepository.deleteAll(order.items)
orderRepository.delete(order)
```

## REP-21 · REP-34 — Entity layer and computed property

```kotlin
@Entity
@Table(name = "\"order\"")                       // reserved word escaped (REP-20)
class Order(
    var memo: String?,
    val createdBy: UUID,
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "member_id")
    val member: Member,
) : BaseTimeEntity() {
    @Id
    val id: UUID = UUID.randomUUID()

    var deletedAt: ZonedDateTime? = null
        protected set

    val isDeleted: Boolean                       // computed property over the backing field
        get() = deletedAt != null

    val memberGrade: MemberGrade                 // delegated — don't duplicate the column
        get() = member.grade
}
```

```kotlin
// ❌ a stored copy of what the other properties already say (REP-34)
var isExpired: Boolean = false                   // must be re-synced whenever expiresAt changes
var totalPrice: Long = 0

// ✅ derived on read; nothing to keep in sync
val isExpired: Boolean
    get() = expiresAt.isBefore(ZonedDateTime.now())
val totalPrice: Long
    get() = unitPrice * quantity
```
