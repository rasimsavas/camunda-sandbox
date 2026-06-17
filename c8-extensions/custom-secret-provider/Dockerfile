# Custom Connectors Bundle with EnvVarSecretProvider
#
# Base image: camunda/connectors-bundle:8.9.5 (latest available 8.9.x)
# Custom JARs are loaded via Spring Boot's PropertiesLauncher from /opt/custom/
# Note: start.sh hardcodes -Dloader.path=/opt/custom/ which overrides any ENV setting

FROM camunda/connectors-bundle:8.9.5

# Add custom connector JARs to the custom connectors directory
COPY target/custom-secret-provider-1.0.0.jar /opt/custom/

# Spring Boot PropertiesLauncher picks up JARs from /opt/custom/ (set via -Dloader.path in start.sh)
