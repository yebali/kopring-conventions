package x

import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.context.annotation.Configuration

@Configuration
@EnableConfigurationProperties(MailProperties::class)
class MailConfig

@ConfigurationProperties(prefix = "mail")
data class MailProperties(
    val host: String,
)
