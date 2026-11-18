# Testing — Worked Examples

Rule text lives in [testing.md](../testing.md) (`TST-*`) and [test-coverage.md](../test-coverage.md) (`COV-*`); each heading names the rule its example illustrates.

## TST-2 — Support classes and Testcontainers

Each module keeps its own `TestcontainersConfiguration` and starts its own containers: PostgreSQL, plus Redis if the module uses it. The wiring rests on three mechanisms:

- **Redis needs `name = "redis"`.** Spring Boot's `RedisContainerConnectionDetailsFactory` does not type-match a plain `GenericContainer`; it matches the `"redis"` connection-name hint, so the bean carries `@ServiceConnection(name = "redis")`. `PostgreSQLContainer` is matched by type and needs no hint. In Testcontainers 2.x `PostgreSQLContainer` is non-generic: declare `PostgreSQLContainer`, not `PostgreSQLContainer<*>`.
- **A database bootstrap runs in the `@Bean`, after `start()`.** A module that needs a raw-JDBC bootstrap before Hibernate `create-drop` (a `CREATE EXTENSION`, named enum types) runs it inside the postgres `@Bean` body right after `start()`, which precedes the `DataSource` and `EntityManagerFactory` beans. `withInitScript` is not used.
- **`application-test.yml` keeps literal `spring.data.redis.host` and `port`** when the base `application.yml` declares the port as a placeholder without a default (`${REDIS_PORT}`): `RedisProperties.port` is a primitive `Int`, so the placeholder must resolve at bind time even though `@ServiceConnection` supplies the live connection. The test yml keeps `host: localhost` / `port: 6379` as bind-time values; the connection details win at runtime.

```kotlin
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfiguration {
    @Bean
    @ServiceConnection
    fun postgresContainer(): PostgreSQLContainer =          // 2.x: non-generic, no <*>
        PostgreSQLContainer(DockerImageName.parse(POSTGRES_IMAGE)).apply {
            withDatabaseName("testdb"); withUsername("test"); withPassword("test")
            start()
            initializeDatabase(this)                         // raw-JDBC bootstrap — before create-drop
        }

    @Bean
    @ServiceConnection(name = "redis")                       // GenericContainer is NOT type-matched
    fun redisContainer(): GenericContainer<*> =
        GenericContainer<Nothing>(REDIS_IMAGE).apply { withExposedPorts(6379) }

    companion object { /* image constants + private bootstrap fns */ }
}

// the three support classes pull the configuration in — no ApplicationContextInitializer / TestPropertyValues:
@WebMvcTest
@ActiveProfiles("test")
@Import(WebConfig::class)                                    // principal resolver, authorization interceptor
abstract class WebMvcTestSupport {
    @Autowired protected lateinit var mockMvc: MockMvc
    @Autowired protected lateinit var objectMapper: ObjectMapper
    @MockkBean protected lateinit var orderService: OrderService   // every Service and Facade a controller injects
    @MockkBean protected lateinit var orderFacade: OrderFacade
}

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class, QuerydslConfig::class)
abstract class DataJpaTestSupport { ... }                    // rolled back by the slice

@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
abstract class SpringBootTestSupport {
    @AfterEach
    fun wipeDatabase() { ... }                               // TRUNCATE … CASCADE over every table but the seed tables (TST-12)
}
```

## TST-3 — Inherited dependencies

```kotlin
// ✅ Good — use inherited dependencies as-is
class OrderServiceTest : SpringBootTestSupport() {
    @Test
    fun `cancels the order`() {
        applicationEventPublisher.publishEvent(event)   // inherited
        orderService.cancel(command)                     // inherited
    }
}

// ❌ Bad — re-declaring dependencies the support class already declares
class OrderServiceTest : SpringBootTestSupport() {
    @Autowired lateinit var applicationEventPublisher: ApplicationEventPublisher
    @MockkBean lateinit var paymentClient: PaymentClient
}
```

## TST-5 · TST-6 — Nested grouping and English names

```kotlin
// ✅ Good — @Nested per domain feature, English backtick names, no @DisplayName
class OrderServiceTest : SpringBootTestSupport() {
    @Nested
    inner class `order creation` {
        @Test fun `creates the order`() { ... }
        @Test fun `rejects the order when stock is short`() { ... }
    }

    @Nested
    inner class `order cancellation` {
        @Test fun `canceling an order sets its status to CANCELED`() { ... }
    }

    @Nested
    inner class `order retrieval` {
        @Test fun `returns the order`() { ... }
    }
}

// ❌ Bad — PascalCase group, @DisplayName, a Korean name, a camelCase name
class OrderServiceTest : SpringBootTestSupport() {
    @Nested
    inner class Create { ... }

    @DisplayName("Create Order")
    @Test
    fun `주문을 생성한다`() { ... }

    @Test
    fun shouldCancelOrder() { ... }
}
```

## TST-8 — Transactional placement

```kotlin
// ✅ Repository test — the @DataJpaTest slice opens the transaction bulk DML needs and rolls it back
class CustomOrderRepositoryImplTest : DataJpaTestSupport() {
    @Test
    fun `deletes every order of the member`() {
        val memberId = UUID.randomUUID()
        val order = buildOrder(memberId = memberId).also(entityManager::persist)

        orderRepository.bulkDeleteByMemberId(memberId)
        entityManager.flush()
        entityManager.clear()                            // bulk DML left the loaded order stale (TST-23)

        assertThat(orderRepository.findByIdOrNull(order.id)).isNull()
    }
}

// ✅ Service test — no @Transactional and no cleanup of its own: the support's wipe removes this test's rows (TST-11)
class OrderServiceTest : SpringBootTestSupport() {
    @Test
    fun `ordering reduces the stock by the ordered quantity`() {
        val product = saveProduct(stock = 10)

        orderService.create(buildCreateOrderCommand(productId = product.id, quantity = 3))

        assertThat(productRepository.findByIdOrNull(product.id)?.stock).isEqualTo(7)
    }
}
```

## TST-9 — Repository query and ordering

```kotlin
// persist data → query with Sort/PageRequest → assert ordering
val memberId = UUID.randomUUID()
entityManager.persist(buildOrder(memberId = memberId, totalPrice = 9_500L))
entityManager.persist(buildOrder(memberId = memberId, totalPrice = 7_500L))
val results = orderRepository.pageByQuery(PageOrderQuery(memberId = memberId, pageable = PageRequest.of(0, 10, Sort.by("totalPrice").descending())))
assertThat(results.content.map { it.totalPrice }).containsExactly(9_500L, 7_500L)
```

## TST-10 — Plain unit test

```kotlin
// plain class (no support class), @Nested, classpath resource loading
class OrderCsvParserTest {
    private fun classpathFile(name: String): Path =
        Path.of(requireNotNull(javaClass.classLoader.getResource("csv/$name")) { "Test resource not found: csv/$name" }.toURI())

    @Nested
    inner class `order CSV parsing` {
        @Test
        fun `turns every row but the header into an order`() {
            assertThat(OrderCsvParser().parse(classpathFile("orders.csv"))).hasSize(3)
        }
    }
}
```

## TST-13 — Fixtures in local scope

```kotlin
// ✅ Good — faker helper + local variables; the success test asserts a derived value (COV-3)
class MemberServiceTest : SpringBootTestSupport() {
    @Test
    fun `registering stores the email in lower case`() {
        val email = randomEmail()
        val member = saveMember(email = email.uppercase())
        assertThat(memberRepository.findByIdOrNull(member.id)?.email).isEqualTo(email)
    }

    private fun saveMember(email: String = randomEmail()): Member =
        memberService.register(RegisterMemberCommand(email = email))  // helper calls service with its input
}

// ❌ Bad — literal identities + class-level properties
class MemberServiceTest : SpringBootTestSupport() {
    private val testEmail = "test@example.com"
    private val testMember by lazy { saveMember() }
    @Test fun `registers`() { val member = Member(email = "x@y.com") }
}
```

## TST-19 — Controller test against a mocked Service

`buildAuth(memberId)` is the support's `RequestPostProcessor` that attaches the authenticated principal (an auth header, or Spring Security's `user(...)`). `orderService` is a `@MockkBean` of `WebMvcTestSupport`.

```kotlin
class OrderControllerTest : WebMvcTestSupport() {
    @Nested
    inner class `order creation` {
        @Test
        fun `POST api_v1_orders returns 201`() {
            val memberId = UUID.randomUUID()
            val productId = UUID.randomUUID()
            val result = buildCreateOrderResult(status = OrderStatus.PENDING)
            every { orderService.createOrder(any()) } returns result

            mockMvc.perform(post("/api/v1/orders").with(buildAuth(memberId))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(CreateOrderRequest(memo = null, items = listOf(CreateOrderRequest.Item(productId = productId, quantity = 1))))))
                .andExpect(status().isCreated)
                .andExpect(header().string(HttpHeaders.LOCATION, "/api/v1/orders/${result.id}"))
                .andExpect(jsonPath("$.status").value(OrderStatus.PENDING.name))

            verify { orderService.createOrder(match { it.memberId == memberId && it.items.single().productId == productId }) }
        }
    }

    @Nested
    inner class `order retrieval` {
        @Test
        fun `GET api_v1_orders_orderId returns 404 when the Service reports no such order`() {
            val orderId = UUID.randomUUID()
            every { orderService.getOrder(any()) } throws OrderNotFoundException(orderId)

            mockMvc.perform(get("/api/v1/orders/$orderId").with(buildAuth(UUID.randomUUID())))
                .andExpect(status().isNotFound)
                .andExpect(jsonPath("$.type").value("ORDER-1000"))
        }
    }

    @Nested
    inner class `order paging` {
        @Test
        fun `GET api_v1_orders passes the status filter and the page size to the Service`() {
            val memberId = UUID.randomUUID()
            every { orderService.pageOrders(any()) } returns buildPageOrderResult()

            mockMvc.perform(get("/api/v1/orders").param("status", OrderStatus.PAID.name).param("size", "5").with(buildAuth(memberId)))
                .andExpect(status().isOk)

            verify { orderService.pageOrders(match { it.memberId == memberId && it.status == OrderStatus.PAID && it.pageable.pageSize == 5 }) }
        }
    }
}
```

## TST-22 — Exception and ErrorCode assertions

```kotlin
// Controller test — the stubbed Service throws; status + ErrorCode in $.type
mockMvc.perform(get("/api/v1/orders/$orderId").with(buildAuth(memberId)))
    .andExpect(status().isNotFound)
    .andExpect(jsonPath("$.type").value("ORDER-1000"))

// Service test — the exception type is the assertion
assertThatThrownBy { orderService.get(UUID.randomUUID()) }
    .isInstanceOf(OrderNotFoundException::class.java)

// Service test — one exception type carries several codes, so the ErrorCode is checked too
assertThatThrownBy { orderService.cancel(command) }
    .isInstanceOf(OrderNotCancelableException::class.java)
    .extracting("errorCode").isEqualTo(ErrorCode.ORDER_ALREADY_SHIPPED)

// ❌ asserting the message
assertThatThrownBy { orderService.cancel(command) }.hasMessage("Order is already shipped")
```

## COV-4 — Private method via public input

```kotlin
// ✅ Good — reach a private branch via a combination of public inputs (this one test covers the deny branch of the private check)
val order = saveOrder()
orderService.ship(ShipOrderCommand(orderId = order.id))
assertThatThrownBy { orderService.cancel(CancelOrderCommand(orderId = order.id)) }
    .isInstanceOf(OrderNotCancelableException::class.java)

// ❌ Bad — calling private directly via reflection / bypassing by relaxing visibility (both prohibited)
OrderService::class.declaredMembers.first { it.name == "checkCancelable" }.call(...)
internal fun checkCancelable(...) { ... }   // do not change production visibility for the sake of tests
```
