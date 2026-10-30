# Configuration Conventions

**Owns:** environment placeholders in `application*.yml` and the shape of `@ConfigurationProperties` classes. **Read when:** adding or changing a property in `application*.yml`, a `*Properties` class, or a `${...}` placeholder referenced from Kotlin.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| CFG-2 | | A required value has no fallback (a bare `${ENV}` placeholder), and its properties class fails fast when it is unset | [§2](#2-environment-values) |
| CFG-3 | | `${ENV:default}` only when "absent" has a defined meaning and the default works correctly | [§2](#2-environment-values) |
| CFG-7 | | Every property Kotlin references is declared in the yml | [§2](#2-environment-values) |
| CFG-12 | | No `@ConfigurationProperties` field that no code reads | [§3](#3-properties-classes) |
| CFG-13 | | `@ConfigurationProperties` classes are registered on the application class | [§3](#3-properties-classes) |
| CFG-14 | | A properties class is a `data class` under `config/` | [§3](#3-properties-classes) |
| CFG-15 | | A property's default lives in the yml only, never repeated as a Kotlin default | [§3](#3-properties-classes) |
| CFG-17 | | A list property is `List<String>`, never a comma-separated string | [§3](#3-properties-classes) |
| CFG-18 | | A duration property is `Duration` with `@DurationUnit`, keeping its name and env key | [§3](#3-properties-classes) |
| CFG-19 | | A value operators tune per environment is a property; anything else is a code constant | [§3](#3-properties-classes) |

Durations in code follow [STY-33](code-style.md#11-time-and-durations).

## 2. Environment values

**CFG-2** — A required value has no fallback: leave it as a bare placeholder like `${DB_HOST}` instead of starting on a guess. A bare placeholder alone does not fail startup for `@ConfigurationProperties`: Boot's `PropertySourcesPlaceholdersResolver` ignores an unresolvable placeholder, so a `String` field binds the literal `"${API_KEY}"` and the application starts — only `@Value` or a type-conversion failure stops it. A properties class therefore checks each required `String` property in `init`; Bean Validation (`@Validated`) is not used ([CTL-14](controller.md#6-validation)).

```kotlin
data class AppProperties(val apiKey: String) {
    init {
        require(apiKey.isNotBlank() && !apiKey.startsWith("\${")) { "app.api-key is not set" }
    }
}
```

**CFG-3** — An optional knob may use `${ENV:default}` only when "absent" has a well-defined meaning and the default works correctly (`${MAIL_RELAY_URL:}` for "no relay", `${STREAM_REPLICAS:1}`).

**CFG-7** — A property referenced from Kotlin is declared in the yml. `@FeignClient(url = "\${...}")` and `@Scheduled(fixedDelayString = "\${...}")` are no exception.

✅ `stream-replicas: ${STREAM_REPLICAS:1}` in the yml, read by a properties class — ❌ a `\${app.foo:1}` that exists only in Kotlin and has no yml declaration.

## 3. Properties classes

**CFG-12** — No `@ConfigurationProperties` field that no code reads. If the only reader of a value is an annotation placeholder, stop at the yml declaration.

**CFG-13** — Every `@ConfigurationProperties` class is registered on the application class, in the `@EnableConfigurationProperties` list, never on a feature `@Configuration`.

```kotlin
@SpringBootApplication
@EnableConfigurationProperties(AppProperties::class, JwtProperties::class)
class OrderApplication
```

**CFG-14** — A properties class is a `data class` in a `config/` package. A `@Configuration` and the properties class it binds may share one file (a carve-out of [STY-12](code-style.md#4-files-and-packages)).

**CFG-15** — A property's default lives in the yml placeholder only (`${ENV:default}`, CFG-3), never also as a Kotlin default value.

```kotlin
// ❌ the default repeated in Kotlin
data class FooProperties(val retentionDays: Int = 365)
// ✅ the yml owns it: retention-days: ${FOO_RETENTION_DAYS:365}
data class FooProperties(val retentionDays: Int)
```

**CFG-17** — A list property is `List<String>`; Spring binds a comma-separated env value (`CORS_ALLOWED_ORIGINS=a,b`) to it. Never a comma-separated `String` parsed by hand.

```kotlin
// ❌ val allowedOrigins: String   →   allowedOrigins.split(",")
// ✅
data class CorsProperties(val allowedOrigins: List<String>)
```

**CFG-18** — A duration property is a `java.time.Duration` with `@DurationUnit(ChronoUnit.X)` matching the unit it is written in, so the property name and its env key (`…Ms`, `FEIGN_READ_TIMEOUT_MS`) keep working with a plain number.

```kotlin
// yml: read-timeout-ms: ${FEIGN_READ_TIMEOUT_MS:5000}
data class FooClientProperties(
    @DurationUnit(ChronoUnit.MILLIS) val readTimeoutMs: Duration,
)
```

**CFG-19** — A value operators tune per environment is a property; anything else is a code constant. A property nobody changes between environments is a constant wearing a configuration costume.
