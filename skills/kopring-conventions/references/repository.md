# Repository Conventions

**Owns:** Repository interfaces, QueryDSL construction, entity mapping, persistence rules, and Flyway migration rules. **Read when:** editing a Repository, Entity, persistence query, or migration.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| REP-1 | | No `@Query` or `@Modifying` on any repository method | [§2](#2-query-construction) |
| REP-2 | | Derived query for a single-row read on one field, QueryDSL `Custom*Repository` for everything else, `@EntityGraph` only for the listed exception | [§2.1](#21-priority) |
| REP-3 | | No stereotype annotation on `Custom*RepositoryImpl` | [§2](#2-query-construction) |
| REP-4 | | No `@Transactional` on `Custom*RepositoryImpl`; at most one collection fetch join per query, none in a paged read | [§2](#2-query-construction) |
| REP-5 | | Extract the `by()` predicate and call it inline; never extract the select–join–where–fetch skeleton | [§2.2](#22-by-predicate) |
| REP-6 | | Use the Q-class default singleton; a self-join alias has a meaningful name | [§2.3](#23-q-class-import) |
| REP-7 | | No QueryDSL projection unless explicitly asked; load the full entity | [§2](#2-query-construction) |
| REP-8 | | Repository names: `findBy`/`existsBy`/`countBy`/`deleteBy`, `listByQuery`, `pageByQuery`, `existsByQuery`, `countGroupedBy{Axis}`, `bulkDeleteBy`; never `get*` | [§3](#3-naming-and-query-objects) |
| REP-9 | | Two or more combined or optional conditions go into one Query object; `list`/`page`/`exists`/`count` stay separate methods | [§3.1](#31-multi-condition-reads) |
| REP-10 | | A paged read uses `PageableExecutionUtils.getPage` and `Page.empty`, never `PageImpl` | [§3.1](#31-multi-condition-reads) |
| REP-11 | | A null filter means no condition; an empty list matches no rows | [§4](#4-filters-and-ordering) |
| REP-12 | | Every ordering ends with the entity id as a tie-breaker | [§4](#4-filters-and-ordering) |
| REP-13 | | Native SQL binds every value as a parameter and reads rows through `Tuple` aliases | [§5](#5-native-sql) |
| REP-14 | | `@Column` only for what Hibernate cannot infer (listed exceptions) | [§6](#6-entity-mapping) |
| REP-15 | | A reference to an entity of the same domain is a `@ManyToOne(fetch = FetchType.LAZY)`, never a raw id field; a reference to another domain's entity is its id only | [§6](#6-entity-mapping) |
| REP-16 | | Enum columns are `@Enumerated(EnumType.STRING)` | [§6](#6-entity-mapping) |
| REP-17 | | A JPA entity's state fields have a `protected set`; state changes through named transition methods (a `@RedisHash` entity: §10) | [§6](#6-entity-mapping) |
| REP-18 | | Transition methods are short verbs without the cause or the target state | [§6](#6-entity-mapping) |
| REP-19 | | `Persistable` only on entities saved in bulk with application-assigned ids | [§6](#6-entity-mapping) |
| REP-20 | | Escape PostgreSQL keywords in `@Table`; no reserved words as property names | [§6](#6-entity-mapping) |
| REP-21 | | Entities carry no Spring dependency; a read that uses a delegated computed property fetch-joins its relation | [§6](#6-entity-mapping) |
| REP-34 | | Keep entities simple: a value derivable from the entity's own properties is a computed `get()` property, never a stored field or column (listed exceptions) | [§6](#6-entity-mapping) |
| REP-22 | | *If the project uses PostgreSQL JSONB:* a JSONB column carries both `@JdbcTypeCode(SqlTypes.JSON)` and `@Column(columnDefinition = "jsonb")` | [§7](#7-jsonb) |
| REP-23 | | *JSONB:* JSONB queries go through one shared JSONB query util; JSONB values compare and sort as text | [§7](#7-jsonb) |
| REP-24 | | *JSONB:* an insert-only entity with nested-collection JSONB is `@Immutable` | [§7](#7-jsonb) |
| REP-25 | | *JSONB:* external payload keys are normalized with `@JsonAlias`; raw payloads are never stored | [§7](#7-jsonb) |
| REP-26 | | *If the project uses pgvector:* embedding similarity goes through `cosineDistanceTo` / `minDistanceTo`; the vector dimension is never hard-coded | [§7](#7-jsonb) |
| REP-27 | | Soft delete is `deletedAt` + `isDeleted` + `delete()`, filtered by one auto-enabled Hibernate `@Filter` that a read may switch off; an own-PK read is filtered in the Service; never `@SQLRestriction`/`@SoftDelete`/`@Where` | [§8](#8-soft-delete) |
| REP-28 | | A unique column on a soft-delete entity has a partial unique index | [§8](#8-soft-delete) |
| REP-29 | | A parent's `@OneToMany`/`@OneToOne` to children it owns cascades `ALL` with `orphanRemoval`, a `@ManyToOne` never; soft-delete parents and high-volume data do not (listed exceptions) | [§9](#9-cascade-and-bulk-delete) |
| REP-30 | | Never mix a bulk delete with entity deletes on one path | [§9](#9-cascade-and-bulk-delete) |
| REP-31 | | *If the project uses Spring Data Redis repositories:* a field used in a derived query is `@Indexed`; a TTL extension uses `EXPIRE`, never a re-`save` | [§10](#10-redis-repositories) |
| REP-32 | | A Flyway migration is immutable once merged to the shared branch; one feature's schema change is one migration | [§11](#11-migrations) |
| REP-33 | | A new unique constraint is named `uq_<table>_<columns>` | [§11](#11-migrations) |
| REP-35 | | A JPA `@Entity`, `@MappedSuperclass` or `@Embeddable` is a plain `class`, never a `data class`, and does not override `equals`/`hashCode`; `plugin.jpa` and all-open are configured (a `@RedisHash` entity is a `data class`: §10) | [§6](#6-entity-mapping) |
| REP-36 | | Every foreign-key column has an index; indexes are `idx_<table>_<columns>`, foreign keys `fk_<table>_<column>` | [§11](#11-migrations) |
| REP-37 | | A migration on a large table never blocks writes: `CREATE INDEX CONCURRENTLY` in its own file, constraints `NOT VALID` then `VALIDATE`, `NOT NULL` after a backfill | [§11](#11-migrations) |
| REP-38 | | A paged read sorts only by the properties its Query object allows; any other `sort` is a 400 | [§4](#4-filters-and-ordering) |
| REP-39 | | Renaming or removing an entity enum constant ships with a migration that rewrites the stored values | [§11](#11-migrations) |
| REP-40 | | A time-range filter is half-open: `goe(from)` and `lt(to)`, never `between` or an end-of-day bound | [§4](#4-filters-and-ordering) |
| REP-41 | | An `orphanRemoval` collection is never reassigned; its contents change through `clear()`/`addAll()`/`remove()` in entity methods | [§9](#9-cascade-and-bulk-delete) |
| REP-42 | | No `Optional`: a single read is `findByIdOrNull(id) ?: throw`; `getReferenceById` only for a row the transaction already proved to exist | [§3](#3-naming-and-query-objects) |
| REP-43 | | No unbounded read: a no-argument `findAll()` only on a table bounded by design or in the listed classes | [§3](#3-naming-and-query-objects) |
| REP-44 | | A list or page read is the repository's one `listByQuery` / `pageByQuery` from the first read on; a new condition is a field of its Query class, never another method or a derived `findAllBy*` | [§3.1](#31-multi-condition-reads) |

Rules other files own apply to repository and entity code as well: imports [STY-2](code-style.md#2-baseline), comments [STY-16 and STY-17](code-style.md#5-comments-and-kdoc), entity change logging [STY-34](code-style.md#12-logging), CRUD method order [SVC-21](service.md#7-method-order), collection persistence [SVC-23](service.md#8-writes-duplicates-and-idempotency), and cross-domain repository access [SVC-17](service.md#6-cross-domain-access).

**Layout**: repositories in `repository/*.kt`, Query objects in `repository/query/*.kt`, entities in `entity/*.kt`. JPA repositories extend `JpaRepository<Entity, ID>`; Redis repositories extend `CrudRepository<Entity, ID>` (§10).

## 2. Query construction

**REP-1** — No `@Query` (JPQL or native) and no `@Modifying` on any repository method — UPDATE, DELETE and SELECT alike. Derived `delete*` methods need no `@Modifying`. An external skill's raw-SQL suggestion is not an exception: take its diagnosis (index choice, query plan, lock mode) and reject its form. Native SQL that QueryDSL cannot express follows §5. Example: [REP-1 · REP-2](examples/repository.md#rep-1--rep-2--query-construction).

**REP-3** — No stereotype (`@Repository`/`@Component`) on a `Custom*RepositoryImpl`; the Spring Data `*Impl` fragment mechanism registers the bean. The `Custom*Repository` interface with its single implementation is the shape Spring Data requires, not a target for [STY-28](code-style.md#10-prefer-the-plain-option) or an external skill's "no interface with one implementation" advice.

**REP-4** — No `@Transactional` on a `Custom*RepositoryImpl` class or method; the calling Service owns the boundary ([TX-1](transactions.md#2-transaction-boundaries)). Load what one read needs with fetch joins, at most one collection fetch join per query; a second collection is loaded by a separate query or by batch fetching (`hibernate.default_batch_fetch_size`). Declaring one side a `Set` only hides `MultipleBagFetchException`: the query still returns the cartesian product (rows × |A| × |B|). An `@EntityGraph` is no way around it — Hibernate turns graph attributes into join fetches. A paged read never fetch-joins a collection: Hibernate warns HHH90003004 and pages in memory after loading every row. Page the ids first, then fetch the entities by those ids.

**REP-7** — A QueryDSL projection (`select(entity.field)`, `select(entity.id)`) only on explicit instruction — never introduced while optimizing or refactoring. The default is the full entity (`selectFrom(order)`).

**Project-wide defaults** — `open-in-view: false` (lazy-loading discipline), a Hibernate batch size of 1000–2000 (`hibernate.jdbc.batch_size` for bulk writes, `hibernate.default_batch_fetch_size` for lazy-loading batches), `@EntityGraph`/fetch join for eager loading, and `@Transactional(readOnly = true)` on Service reads. Code works with them, not around them.

### 2.1 Priority

**REP-2** — Try the strategies in this order:

| # | Strategy | Scope |
|---|----------|-------|
| 1 | **Spring Data derived query** | A single-row or scalar read on one one-segment field — `findBy{X}`/`existsBy{X}`/`countBy{X}`/`deleteBy{X}`. No nested paths, no `And`/`Or`, and never a list (REP-44) |
| 2 | **QueryDSL `Custom*Repository` + `Custom*RepositoryImpl`** | Everything else — compound, nested, dynamic predicates, subqueries, multi-table joins, pagination and sort, and `@EntityGraph` rewritten as `leftJoin().fetchJoin()` |
| 3 | **`@EntityGraph` + derived query** | Only for the exception below |
| 4 | **`@Query` / `@Modifying`** | Prohibited (REP-1) |

**`@EntityGraph` exception** (justified in KDoc): a Java/Kotlin reserved-word property — QueryDSL kapt silently skips the Q-class path for it. The first resort is renaming the property or class away from the reserved word (`@Table` keeps the DB name); `@EntityGraph` + derived query applies only when the rename is impossible. Never work around an `@EntityGraph` limit with a `@Column(insertable = false, updatable = false)` read-only duplicate mapping (REP-14).

Example: [REP-1 · REP-2](examples/repository.md#rep-1--rep-2--query-construction).

### 2.2 by() predicate

**REP-5** — Extract the conditions into `private fun by(query): BooleanBuilder`, reused by the content query and the count query, and call it inline as `.where(by(query))` at every use site. Do not hoist it to `val where = by(query)` ([STY-19](code-style.md#6-single-use-intermediates); `by()` is a cheap builder, harmless to call twice), and never assemble a `BooleanBuilder` imperatively inside `pageByQuery()`. The skeleton half of REP-5 is §2.4.

Example: [REP-5](examples/repository.md#rep-5--by-predicate-extraction).

### 2.3 Q-class import

**REP-6** — Import the kapt-generated singleton; no local alias fields (`private val order_ = QOrder("order_")`).

- **Self-join** — the same table twice needs a second alias: name it by meaning (`parentCategory`, `ancestorCategory`), never with a formal suffix (`category_`).
- **Reserved-word entity name** — QueryDSL generates the singleton as `keyword$`; hide the `$` with a Kotlin rename import, not an alias field.

Example: [REP-6](examples/repository.md#rep-6--q-class-import-and-self-join-alias).

### 2.4 Query skeleton stays inline

Write the full `selectFrom…join…where…fetch` chain inside each method so it maps 1:1 to the executed SQL (REP-5). Skeletons are not shared across repositories or strategies (service-layer QueryDSL strategies included) — query-skeleton duplication is not a [STY-15](code-style.md#4-files-and-packages) target.

| Allowed (reads inline inside the chain) | Forbidden (hides the query shape from the call site) |
|---|---|
| A `by()` predicate reused by the content and count queries | The whole select–join–where–fetch skeleton in a separate method |
| A chainable extension such as `withPagination()` or `jsonbField()` | The pagination tail (`.withPagination().fetch()` + `PageableExecutionUtils.getPage`) in a `pageOf()`-style helper |
| Conditions encapsulated in a Query object (`Page*Query`, `Exists*Query`) | A shared skeleton in an interface default method such as `executeMatchingQuery()` |

A line comment inside the chain sits only on a `join`/`where`/`orderBy` step whose reason the operator does not show (`.where(category.path.like("$prefix/%")) // 하위 트리 전체`), never on `.fetch()` or a self-explanatory step.

Example: [REP-5](examples/repository.md#rep-5--query-skeleton-stays-inline).

## 3. Naming and query objects

**REP-8** — Repository methods use these names:

| Type | Method prefix | Return | Query class |
|------|---------------|--------|-------------|
| Single | `findBy*` / `existsBy*` / `countBy*` / `deleteBy*` | `Entity?` / `Boolean` / `Long` | not needed |
| Multiple | `listByQuery(query)` ([REP-44](#31-multi-condition-reads)) | `List<Entity>` | `List*Query` required |
| Paginated | `pageByQuery(query)` | `Page<Entity>` | `Page*Query` required |
| Existence (condition-branching) | `existsByQuery(query)` | `Boolean` | The `List*Query` of the same filter axis, else `Exists*Query` |
| Count (condition-branching) | `countByQuery(query)` | `Long` | The `List*Query` of the same filter axis, else `Count*Query` |
| Count (GROUP BY distribution) | `countGroupedBy{Axis}(query)` | `Map<Enum, Long>` | `Count*Query` (one method per axis, Query shared) |

`get*` is a Service prefix; repositories use `find*` for single, `list*` for multiple, `page*` for paged.

- **One filter axis, one Query class** — an `exists`/`count` read on a list read's filter axis takes its `List*Query` (`existsByQuery(ListOrderQuery)`, REP-9); `Exists*Query`/`Count*Query` name an axis that only an existence or count read uses.
- **Bulk delete is `bulkDeleteBy*`** — a QueryDSL `delete` in a `Custom*RepositoryImpl` is never named `deleteAllBy*`: that reads as a Spring Data derived delete, which removes entity by entity, and REP-30 depends on telling the two apart at the call site.
- **Standard names are `listByQuery`/`pageByQuery`** — entity-baked variants (`pageOrders`, `findPageBy`) are prohibited. A descriptive name is allowed only when one entity needs more than one distinct paged projection (e.g. `pageWithItemSummary` beside `pageByQuery` on `Order`); the entity's main filtered page is always `pageByQuery`.
- **GROUP BY distribution count** — `countBy*` is a derived-query prefix and reads as "filtered count", so the grouping axis is named `countGroupedBy{Axis}(query): Map<Enum, Long>` (`countGroupedByStatus`). The filter axis is carried by the `Count*Query` type, not the name; two axes get two methods sharing the Query. A family that returns a projection list (e.g. counts grouped by product and status together) is not `Map<Enum, Long>` and is outside this naming rule.

**REP-42** — Production code uses no `java.util.Optional`. A single read is `findByIdOrNull(id) ?: throw …` (Spring Data's Kotlin extension), and a derived single read returns `Entity?` (REP-8); `findById(id).orElseThrow { … }`, `.get()` and `.isPresent` are the Java spelling of the same thing. A framework signature that demands `Optional` (`AuditorAware`, `DateTimeProvider`) is the exception, and a Java API's `Optional` result is unwrapped at once with `getOrNull()`. `getReferenceById` returns an unloaded proxy without checking that the row exists, so a missing id surfaces as a foreign-key violation at flush or as JPA's own `EntityNotFoundException` on first access — a 500 where the Service owes its domain's 404. It is therefore only a way to set a foreign key (REP-15) to a row the same transaction already proved to exist — loaded, locked or just inserted, as in a bulk ingest under one parent — and never the read of an id a caller supplied; that read loads the entity ([SVC-2](service.md#2-method-signatures)).

✅ `orderRepository.findByIdOrNull(id) ?: throw OrderNotFoundException(id)` — ❌ `orderRepository.findById(id).orElseThrow { OrderNotFoundException(id) }` · `OrderItem(product = productRepository.getReferenceById(command.productId), …)`

**REP-43** — No unbounded read. A no-argument `findAll()` (or `findAll(sort)`) loads a table whose size nobody controls, so it appears only on a table bounded by design — a fixed code table, the settings rows of one service — and in the classes of [service.md §6.2](service.md#62-repository-access-exceptions) (the full wipe and the seeders). A read over rows that accumulate takes a bounding condition (an owner, a parent id, a period) or a `Pageable`; a job that must visit every row walks it in id-ordered chunks, one transaction per chunk. The endpoint side is [CTL-34](controller.md#9-paging).

### 3.1 Multi-condition reads

**REP-9** — A read with two or more combined conditions, or nullable optional filters, does not spawn one derived method per combination (`existsByProductIdAndOrderPaidAtIsNotNull` and its forks). Its conditions go into a Query object behind a single `*ByQuery` method, and the call site states intent through named arguments. A single-row read on one field (`findById`, `findByCode`) stays derived; `@Query` JPQL is never the way around it (REP-1).

- **`list`/`page`/`exists`/`count` are always separate methods** — a different return shape is never folded into one method. Only methods on the same filter axis share a `by(query)`: `listByQuery(ListOrderQuery)` and `existsByQuery(ListOrderQuery)` share one filter and one `by()`, while `pageByQuery(PageOrderQuery)` has its own axis (period, explicit id list) and its own `by()`.

**REP-44** — A repository has one `listByQuery(List*Query)` and one `pageByQuery(Page*Query)`, and a list read is written that way from the entity's first one: never a derived `findAllBy*`, and never a second list or page method beside the first. A new list or page need adds a nullable field to the Query class — `null` adds no condition (REP-11) — and the method loads the superset fetch graph its callers read, still with at most one collection fetch join (REP-4); a further collection is batch-fetched or loaded by a separate query. What stays outside the single method:

- **Own-PK reads** — `findById`, fetch-graph variants `findByIdWith*`, and multi-PK `listByIds(ids…)`/`listByIdsWith*` are keyed on the entity's own id.
- **Mechanically distinct reads** — reads that cannot share one query skeleton. For a path-addressed tree entity: the paged listing of one level of children (prefix `LIKE` + `notLike` `%/%`) or of a name match over the subtree, the unpaged whole subtree (`listDescendants`, prefix `LIKE`), a multi-prefix age sweep (OR of path prefixes + `createdAt <`), exact `IN` (`listByPaths`), or a different traversal.
- **A different return shape** — a projection asked for explicitly (REP-7) is a method of its own (`pageWithItemSummary`, REP-8).
- **A Redis repository** has no QueryDSL (REP-31); its list reads stay derived.

**REP-10** — A paged read builds its page with `PageableExecutionUtils.getPage(content, pageable) { countQuery }`, which skips the count query on a partial last page, never with `PageImpl(content, pageable, count)`. An empty short-circuit returns `Page.empty(pageable)`, never `PageImpl(emptyList(), pageable, 0L)`.

Example: [REP-9](examples/repository.md#rep-9--query-object-clustering).

## 4. Filters and ordering

**REP-11** — In a Query object a `null` filter adds no condition, and an empty list matches no rows:

```kotlin
.and(query.ids?.let { if (it.isEmpty()) Expressions.FALSE.isTrue else order.id.`in`(it) })
```

Never `takeIf { it.isNotEmpty() }` to mean "all": it turns an empty selection into every row.

**REP-12** — Every ordering ends with the entity id ascending as a tie-breaker, so offset paging never skips or repeats rows. A client's `Sort` goes through the project's one shared `Sort` → `OrderSpecifier` transformer (`orderTransformer = OrderSpecifierTransformer(order)`): `transform(sort, sortable)` resolves each property to a path of the entity — an association path as an implicit join, a JSONB map key as its text value (REP-23) — and rejects a property outside `sortable`, the Query object's `SORTABLE` set (REP-38):

```kotlin
.orderBy(order.orderedAt.desc(), order.id.asc())   // fixed ordering
.withPagination(query.pageable, *orderTransformer.transform(sort = query.pageable.sort, sortable = PageOrderQuery.SORTABLE), order.id.asc())   // paged form, client sort
```

**REP-38** — The `Sort` of a paged read comes from the client's `?sort=`, and the shared `Sort` → `OrderSpecifier` transformer (REP-12) resolves any mapped path: an association path (an implicit join), an unindexed column of a large table, a field the client may not see, a JSONB key. Each `Page*Query` declares the properties it sorts by (`companion object { val SORTABLE = setOf("createdAt", "status") }`), the transformer receives that set, and a property outside it raises the domain's 400. REP-12's id tie-breaker is appended after the allowed properties.

**REP-40** — A time-range filter is half-open, `[from, to)`: the predicate is `goe(from)` and `lt(to)`, and the Query object's bounds mean exactly that (`startOrderedAt` inclusive, `endOrderedAt` exclusive). Never QueryDSL `between`, which includes both ends, and never an end bound built as the last instant of a day (`23:59:59`, `plusDays(1).minusNanos(1)`): `timestamptz` keeps microseconds, so the rows of that last fraction are dropped, and two adjacent `between` ranges count the row on their shared bound twice. A calendar-day range from the client becomes instants once, in the Command: `from.atStartOfDay(zone).toInstant()` up to `to.plusDays(1).atStartOfDay(zone).toInstant()` in the application time zone ([STY-30](code-style.md#11-time-and-durations)).

```kotlin
.and(query.startOrderedAt?.let { order.orderedAt.goe(it) })
.and(query.endOrderedAt?.let { order.orderedAt.lt(it) })
```

## 5. Native SQL

**REP-13** — Native SQL binds every value with `setParameter`; only fixed fragments chosen in code may be concatenated into the SQL string. Rows are read through `createNativeQuery(sql, Tuple::class.java)` and column aliases, never through positional `Array<*>` casts.

```kotlin
// ✅ bound value, row read by alias
entityManager.createNativeQuery("SELECT p.id AS id, p.stock AS stock FROM product p WHERE p.sku LIKE :prefix", Tuple::class.java)
    .setParameter("prefix", "$prefix%")
    .resultList.map { (it as Tuple).get("stock", Long::class.javaObjectType) }

// ❌ value concatenated into the SQL, row read by position
entityManager.createNativeQuery("SELECT p.id, p.stock FROM product p WHERE p.sku LIKE '$prefix%'")
    .resultList.map { (it as Array<*>)[1] as Long }
```

## 6. Entity mapping

**REP-14** — `@Column` is for what Hibernate cannot infer — nothing else.

| Option | Use | Reason |
|--------|-----|--------|
| `name` | ❌ | `PhysicalNamingStrategy` maps camelCase to snake_case (`shippedAt` → `shipped_at`) |
| `nullable` | ❌ | NOT NULL is owned by the Flyway migration, and `ddl-auto=validate` does not check nullability — the annotation shapes only the `create-drop` test schema and `update` local DDL, where a NOT NULL catches nothing the non-null Kotlin type has not already rejected at compile time |
| `insertable` / `updatable` | ❌ | One column is never mapped twice. A same-domain reference is a `@ManyToOne` read through `foo?.id`, another domain's row is one id column (REP-15); Kotlin `val` gives code-level read-only |
| `columnDefinition` | ✅ | PostgreSQL types Hibernate cannot infer: `jsonb`, `text` |
| `length` | ✅ | Only when ≠ the default 255 |
| `unique` | ❌ | Unnamed, it becomes `UK<hash>` in the `create-drop` test schema, where SVC-24's match by name never fires. Declare `@Table(uniqueConstraints = [UniqueConstraint(name = "uq_<table>_<columns>", columnNames = [...])])` under the migration's constraint name (REP-33). A column with a partial unique index (REP-28) declares no unique constraint in the mapping — that index lives only in the migration |

Accepted exceptions:

- **Creation-timestamp columns** may carry `@Column(updatable = false)` for `AuditingEntityListener` cooperation (`BaseTimeEntity.createdAt`, with `@EntityListeners(AuditingEntityListener::class)` + `@CreatedDate`). `lastModifiedAt` stays unannotated.
- **A DB-generated column** is mapped `insertable = false, updatable = false`.
- **A `@MapsId` derived identifier** has no `@Column(name = …)` on the `@Id` field — with `@MapsId` the id column is the association's `@JoinColumn`.
- **`@IdClass` key fields** each carry `@Column(name = …)` when the project configures `ImplicitNamingStrategyComponentPathImpl`: it treats the id class as a component and would name the columns `id_<field>`.

Example: [REP-14](examples/repository.md#rep-14--entity-column-policy).

**REP-15** — A reference to an entity of the same domain (the same `<domain>` package) is a `@ManyToOne(fetch = FetchType.LAZY)` (`OrderItem.order`, read through `item.order.id`), never a separate `orderId: UUID` field. `fetch = FetchType.LAZY` is always written: the JPA default for `@ManyToOne` is EAGER. A reference to an entity of another domain is its id only (`Order.memberId: UUID`, `OrderItem.productId: UUID`): an entity imports no other domain's entity, so loading one domain's row never reaches into another's, and the other domain's data comes from its Service ([SVC-17](service.md#6-cross-domain-access), [SVC-39](service.md#6-cross-domain-access)). A query that must filter or sort by another domain's column joins on the id (`.innerJoin(member).on(member.id.eq(order.memberId))`) and selects only its own entity. The id column still carries its foreign-key constraint and index in the migration (REP-36) — the domains of one deployable share one database. An id of a row another service owns is a plain `UUID` with no constraint.

**REP-16** — An enum column is `@Enumerated(EnumType.STRING)`.

**REP-17** — A JPA entity's state fields are `var … protected set` and change only through named transition methods; no caller assigns them directly. A `@RedisHash` entity keeps its state in constructor `var`s instead ([REP-31](#10-redis-repositories)); its changes still go through named methods.

**REP-18** — Transition methods are short verbs — `Order.hold()`/`complete()`/`cancel()`, `Payment.approve()`/`fail()`/`refund()`. The cause stays out of the name (`failByTimeout` — the cause belongs in the caller's log), and so does the target state (`resetToPending`). Qualify a name only to tell siblings apart, and give a variant that also changes side state (a counter) its own method (`reset` vs `reassign`). DTO names follow [STY-50](code-style.md#16-filler-suffixes-and-dto-casing); this is the entity counterpart.

**REP-19** — `Persistable<UUID>`, with a `@Transient` new flag cleared in `@PostPersist`/`@PostLoad`, only on entities saved in bulk with application-assigned ids. Without it, `save` treats an entity whose id is already set as existing and merges it with a SELECT before the INSERT; that cost matters only for bulk saves, so no other entity implements it.

**REP-20** — Escape PostgreSQL keywords in `@Table(name = "\"order\"")`, and keep reserved words out of property names (`sequence`, not `order`) — a reserved word also breaks QueryDSL kapt (the §2.1 `@EntityGraph` exception).

**REP-21** — `@Entity` + `@Table`; computed values in `get()` backing-property style; `@EntityListeners` for lifecycle hooks; no Spring dependency in `entity/`. A same-domain related entity's value is delegated through a computed property instead of a duplicated column (`OrderItem.orderedAt get() = order.orderedAt`); the related entity must be loaded (`@EntityGraph`/`fetchJoin()`) before the property is read outside a transaction, or `LazyInitializationException` fires. A list read whose callers use a delegated property fetch-joins that relation; otherwise each row lazy-loads it inside the transaction — a silent N+1.

**REP-34** — Keep an entity simple: a property holds a fact that cannot be derived, and a value that follows from the entity's other properties is computed in a `get()` property instead of being stored (`isDeleted` from `deletedAt`, `OrderItem.totalPrice` from `unitPrice * quantity`). A value judged against the current time is a method taking the time (`isExpiredAt(now)`), not a getter that reads the clock. Do not add a column, a `var` or a transition-method assignment for it: a stored copy can disagree with its inputs, and each new input then has to be synchronized by hand. Exceptions: a value a query must filter or sort on in the database (a getter is invisible to QueryDSL — derive it in the predicate from the stored inputs, and store it only when that predicate cannot be indexed or is too costly), and a snapshot that must stay fixed when its inputs change later (an order's price at purchase time).

Example: [REP-21 · REP-34](examples/repository.md#rep-21--rep-34--entity-layer-and-computed-property).

**REP-35** — A JPA `@Entity`, `@MappedSuperclass` or `@Embeddable` class is a plain `class`, never a `data class`: a generated `equals`/`hashCode`/`toString` reads every property, so it initializes LAZY associations, recurses through bidirectional ones, and changes its hash when a field changes, which loses the entity inside a `HashSet`. An entity does not override `equals`/`hashCode` either: within one persistence context Hibernate keeps one instance per row, so identity equality holds, and code comparing entities across contexts compares ids. The build applies `kotlin("plugin.jpa")` (no-arg constructors) and all-open for `@Entity`, `@MappedSuperclass` and `@Embeddable`; without all-open a final Kotlin class cannot be proxied, and every LAZY to-one loads eagerly. A `@RedisHash` entity is not a JPA type and is a `data class` with every persisted field in its constructor ([REP-31](#10-redis-repositories)).

## 7. JSONB

*If the project uses PostgreSQL JSONB.*

**REP-22** — A JSONB column carries both `@JdbcTypeCode(SqlTypes.JSON)` and `@Column(columnDefinition = "jsonb")`. `@JdbcTypeCode` drives the JSON serialization, and with the PostgreSQL dialect it alone maps to `jsonb`; `columnDefinition = "jsonb"` makes the column type explicit for schema generation and validation and for readers.

**REP-23** — JSONB queries go through one shared JSONB query util: a `.jsonbField(vararg keys)` extension extracts the value as text, then `.containsIgnoreCase()`, `.eq(...)`. There is no numeric cast — a JSONB value compares and sorts as text. Sorting goes through the shared `Sort` → `OrderSpecifier` transformer ([REP-12](#4-filters-and-ordering)); a property whose first segment is a JSONB map field (`metadata.priority`) orders by that key's text value, so numbers sort lexicographically (`"10"` before `"9"`). There is no per-field cast; the sortable properties are limited by REP-38.

**REP-24** — An insert-only entity carrying a JSONB value with a nested collection (`snapshot = {"items": [{"sku": "A-1", "quantity": 2}]}`) is `@org.hibernate.annotations.Immutable`. Hibernate's JSON type does not deep-copy the snapshot, so such a value is judged dirty on every flush and each inserted row gets a redundant UPDATE; flat maps do not reproduce it.

- **Target**: an entity with no update path (all-`val` constructor; the repository only `saveAll`, reads and deletes) carrying such a field.
- **Apply even when callers pass an empty value** — the criterion is the entity's declared shape (insert-only + JSONB), not the values callers pass.
- ❌ Never on an updatable entity — `@Immutable` silently ignores dirty-checked UPDATEs, and Hibernate rejects a bulk UPDATE on it (a bulk DELETE is allowed). Check `var` fields and repository call sites first.

**REP-25** — External payload keys are normalized with Jackson `@JsonAlias` on the typed payload class's properties (`PaymentApproval.approvalNumber` aliases `approvalNo`). A mapper converts the raw payload into the typed class, which serializes it into the JSONB column (`payment.approval`). The raw external payload is never stored verbatim.

**REP-26** — *If the project uses pgvector.* Use `cosineDistanceTo` for one embedding and `minDistanceTo(embeddings)` for many; the latter wraps PostgreSQL `LEAST()` across the reference embeddings, and a single embedding yields the distance directly. Both live in one shared query util. Convert a similarity threshold with `maxCosineDistance = 1.0 - minSimilarity` (`minSimilarity` runs 0.0–1.0, 1.0 = identical); cosine distance runs from 0.0 (identical) to 2.0 (opposite). The embedding dimension differs per column: never hard-code it, read it from the column definition (`vector(N)`).

Example: [REP-22 · REP-23 · REP-24](examples/repository.md#rep-22--rep-23--rep-24--jsonb).

## 8. Soft delete

**REP-27** — An entity that keeps a deletion trail has a nullable `deletedAt` instead of a physical delete, in three fixed pieces: the `deletedAt` column (`protected set`), an `isDeleted` getter, and a `delete(now)` transition method that logs only the field it assigns ([STY-34](code-style.md#12-logging)). Deleted rows are left out by one Hibernate filter: `@FilterDef(name = SOFT_DELETE_FILTER, defaultCondition = "deleted_at is null", autoEnabled = true)` is declared once, next to the base entity, and each soft-delete entity — and each mapped collection of one — carries `@Filter(name = SOFT_DELETE_FILTER)`. Every query Hibernate builds, QueryDSL and derived alike, then excludes deleted rows, and no predicate repeats `deletedAt.isNull`. The filter does not apply to a lookup by primary key (`findById`, loading a `@ManyToOne`) or to a to-one join (`join fetch item.order` returns a deleted parent), so an own-PK read may return a deleted row and the Service drops it through its `getActiveEntity` ([SVC-18](service.md#6-cross-domain-access)) or an `isDeleted` check. `existsById` and `findAllById` are queries, so they are filtered. A read that must see deleted rows — a super-admin or audit screen — switches the filter off for its own transaction through the one shared helper, `softDeleteFilter.includingDeleted { … }`, never through native SQL or a second mapping of the table. Never `@SQLRestriction`, `@SQLDelete`, `@Where` or `@SoftDelete`: none can be switched off for one read, and `@SoftDelete` takes the deletion time from the database clock ([STY-58](code-style.md#11-time-and-durations)). One repository test per module pins the three behaviours ([COV-5](test-coverage.md#4-areas-that-must-have-a-standalone-test)).

The default shape of the helper; a project may already have its own equivalent — use that:

```kotlin
@Component
class SoftDeleteFilter(private val entityManager: EntityManager) {
    fun <T> includingDeleted(block: () -> T): T {
        val session = entityManager.unwrap(Session::class.java)
        session.disableFilter(SOFT_DELETE_FILTER)
        try {
            return block()
        } finally {
            session.enableFilter(SOFT_DELETE_FILTER)
        }
    }
}
```

It runs inside the calling Service method's transaction ([TX-1](transactions.md#2-transaction-boundaries)); outside one there is no session to switch.

**REP-28** — A unique column on a soft-delete entity has a partial unique index (`WHERE deleted_at IS NULL`); a plain UNIQUE lets a deleted row occupy the value forever and blocks re-registration with the same code.

- **Partial indexes exist only where Flyway runs.** JPA `@Table`/`@Column` cannot express a `WHERE` clause, so the mapping declares no unique constraint on such a column (REP-14), and a profile on `ddl-auto: create-drop` (tests) or `update` (local) has no unique constraint on such a column — duplicate codes are accepted there. Tests account for this.
- **Accepted non-partial exceptions**: a value that must stay occupied after soft delete (an email that can never be re-registered, an ordinal a deleted row keeps) uses a plain UNIQUE on purpose.

Example: [REP-27 · REP-28](examples/repository.md#rep-27--rep-28--soft-delete-shape).

## 9. Cascade and bulk delete

**REP-29** — A parent's `@OneToMany`/`@OneToOne` to the children it owns as an aggregate declares `cascade = [CascadeType.ALL], orphanRemoval = true`, backed by DB `ON DELETE CASCADE` (defense in depth). Never cascade from a `@ManyToOne`: it is JPA's owning (foreign-key) side, so a cascaded `REMOVE` there deletes the parent with the child.

- **Soft-delete entities** (REP-27) cascade nothing; the Service handles deletion explicitly. Accepted exception: a collection that is the soft-delete parent's live child set, replaced as a whole on every edit (`Order.items` on every order edit), keeps `cascade = ALL, orphanRemoval = true` — the parent row is only soft-deleted, so the cascade never removes it.
- **High-volume accumulating data** (event logs, per-order tracking records) has no `@OneToMany` on its parent — loading it would risk OOM.

**REP-41** — A collection mapped with `orphanRemoval = true` (REP-29) is created once and never reassigned: `val items: MutableList<OrderItem> = mutableListOf()`, changed only inside the entity's named methods (REP-17) through `clear()`, `addAll()` and `remove()`; callers read it and never call its mutators. Hibernate finds orphans through the collection instance it loaded, so assigning a new list (`items = newItems`) drops that instance and the flush throws instead of deleting the removed children. Replacing the whole set (REP-29's `Order.items`) is `items.clear()` followed by `items.addAll(newItems)`.

**REP-30** — A JPQL bulk delete (QueryDSL `queryFactory.delete`, named `bulkDeleteBy*` by REP-8) is never mixed with entity deletes on one path (`TransientObjectException`, session inconsistency): a path deletes entities throughout, or runs bulk deletes only.

Example: [REP-30](examples/repository.md#rep-30--bulk-delete-mixing).

## 10. Redis repositories

*If the project uses Spring Data Redis repositories.*

**REP-31** — A Spring Data Redis repository is `CrudRepository<Entity, ID>` over a `@RedisHash` entity. It has no QueryDSL, `@EntityGraph` or fetch join, and the `@Column` policy (REP-14) does not apply; derived queries (REP-2 row 1) and REP-1 do. A field used in a derived query carries `@Indexed`, or the lookup loads the whole set and filters in memory (`CheckoutSessionRepository.findByMemberId`).

A `@RedisHash` entity declares every persisted field, state included, as a constructor property (`data class CheckoutSession(…, var failureCount: Int = 0, …)`). Spring Data Redis writes body properties to the hash but does not populate them on read, so a body property or a `protected set` state field comes back with its initializer value.

Rolling a `@RedisHash` entity's TTL forward uses `EXPIRE`, never `save`: `save` deletes and rewrites the key and refreshes every `@Indexed` secondary index, issuing a Redis `KEYS` per index. Redis is single-threaded, so a re-save on a hot path stalls every other client.

## 11. Migrations

**REP-32** — A `db/migration/V*.sql` may be edited or renumbered until it is merged to the shared branch; after that it is immutable, in content and filename — teammates' local databases and CI may already have applied it, and an edit alters its Flyway checksum (a rename leaves the applied version unresolved), so Flyway's validate-on-migrate fails at boot (`FlywayValidateException`). Schema evolves through a new versioned migration — a rename too is a new `V*` with `ALTER TABLE … RENAME`. One feature's schema change is one migration file: it is not split into `V5`/`V6` per sub-task, and while it is unmerged each sub-task's change folds into the feature's file.

**REP-33** — A new unique constraint is named `uq_<table>_<columns>` (`uq_order_item_order_id_product_id`). Constraints in merged migrations keep their names (REP-32).

**REP-36** — PostgreSQL does not index a foreign-key column by itself. Every foreign key (each reference of REP-15, an association or an id column, is one) gets an index in the migration that adds it, unless a composite index or unique constraint already leads with that column; without it a parent delete (`ON DELETE CASCADE`, REP-29) and every child lookup by parent scan the child table. Names: `idx_<table>_<columns>` for an index and `fk_<table>_<column>` for a foreign key (`idx_order_item_order_id`, `fk_order_item_order_id`), beside REP-33's `uq_`. Names in merged migrations stay (REP-32).

**REP-37** — On a table large enough that a scan or rewrite takes noticeable time, a migration never holds a write-blocking lock for that long. `CREATE INDEX` blocks writes for its whole build, so an index is built `CONCURRENTLY`, which cannot run inside a transaction: it goes in a migration file of its own — Flyway runs a script holding only non-transactional statements outside a transaction and rejects one that mixes both — the one exception to REP-32's one file per feature. A foreign key or check constraint is added `NOT VALID` and checked by a later `VALIDATE CONSTRAINT`, which takes a weaker lock. A `NOT NULL` column on existing rows is added nullable (or with a constant `DEFAULT`, which PostgreSQL 11+ adds without a rewrite), backfilled, then set `NOT NULL`. Such a migration starts with `SET lock_timeout`, so a blocked migration fails instead of queueing every write behind it.

**REP-39** — An enum column stores the constant's name (REP-16), and Hibernate throws while loading a row whose value no constant matches, so every read that touches such a row fails. A change that renames or removes a constant of an entity enum carries, in the same change, a new migration (REP-32) that rewrites the stored values (`UPDATE "order" SET status = 'CANCELED' WHERE status = 'CANCELLED'`); the rows of a removed constant move to the constant that replaces it. Adding a constant needs no migration, unless a migration put a `CHECK` constraint on the column — then the same change widens it. The service-layer enum renames freely, because only the mapper follows ([SVC-27](service.md#9-enum-layer-separation)).
