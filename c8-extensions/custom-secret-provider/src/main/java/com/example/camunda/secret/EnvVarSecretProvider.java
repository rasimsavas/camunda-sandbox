package com.example.camunda.secret;

import io.camunda.connector.api.secret.SecretContext;
import io.camunda.connector.api.secret.SecretProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Custom SecretProvider that reads secrets from environment variables
 * with integer processing (multiply by 2).
 *
 * <p>Lookup algorithm:
 * <ol>
 *   <li>Look for the exact environment variable name (e.g. {@code MY_API_KEY}).</li>
 *   <li>If not found, look for it with a {@code SECRET_} prefix (e.g. {@code SECRET_MY_API_KEY}).</li>
 *   <li>If found:
 *     <ul>
 *       <li>Log at INFO: which env var resolved the secret.</li>
 *       <li>If value is a valid integer → parse, multiply by 2, log both values at INFO
 *           (these are numbers, not sensitive strings).</li>
 *       <li>If not an integer → return raw value, log metadata only at INFO
 *           (never log secret value itself at INFO).</li>
 *     </ul>
 *   </li>
 *   <li>If not found, log at DEBUG and return {@code null} (never throw — that
 *       breaks the SPI provider chain).</li>
 * </ol>
 */
public class EnvVarSecretProvider implements SecretProvider {

    private static final Logger LOG = LoggerFactory.getLogger(EnvVarSecretProvider.class);
    private static final String SECRET_PREFIX = "SECRET_";

    @Override
    @Deprecated
    public String getSecret(String name) {
        return getSecret(name, null);
    }

    @Override
    public String getSecret(String name, SecretContext context) {
        if (name == null || name.isEmpty()) {
            return null;
        }

        String rawValue = null;
        String resolvedVar = null;

        // 1. Try exact match
        rawValue = System.getenv(name);
        if (rawValue != null) {
            resolvedVar = name;
        }

        // 2. Try with SECRET_ prefix (avoid double-prefixing)
        if (rawValue == null && !name.startsWith(SECRET_PREFIX)) {
            resolvedVar = SECRET_PREFIX + name;
            rawValue = System.getenv(resolvedVar);
        }

        // 3. If found — process the value
        if (rawValue != null) {
            return processValue(name, resolvedVar, rawValue);
        }

        // 4. Not found — return null to let other providers in the chain try
        LOG.debug("Secret '{}' not found in environment variables (tried '{}' and '{}')",
                name, name, SECRET_PREFIX + name);
        return null;
    }

    /**
     * Process a resolved secret value.
     * <ul>
     *   <li>If the value is a valid integer, multiply by 2 and return the result.</li>
     *   <li>If the value is a string, return it as-is (never log string values at INFO).</li>
     * </ul>
     */
    private String processValue(String secretName, String envVarName, String rawValue) {
        LOG.info("Resolved secret '{}' from environment variable '{}'", secretName, envVarName);

        // Try integer processing
        try {
            int intValue = Integer.parseInt(rawValue);
            int doubled = intValue * 2;
            LOG.info("Secret '{}' = {} → processed to {} (x2)", secretName, intValue, doubled);
            return String.valueOf(doubled);
        } catch (NumberFormatException e) {
            // Not an integer — return raw value as-is; log only metadata at INFO
            LOG.info("Secret '{}' resolved as string, returned as-is", secretName);
            LOG.debug("Secret '{}' = '{}' (string, returned as-is)", secretName, rawValue);
            return rawValue;
        }
    }
}
