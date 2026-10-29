import java.util.Properties

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.android.lint)
    `java-test-fixtures`
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        allWarningsAsErrors.set(true)
    }
}

val promptsDir =
    rootProject.layout.projectDirectory.dir(
        "../Sources/WritingAssistantCore/Resources/Prompts",
    )

sourceSets {
    create("liveTest") {
        compileClasspath += sourceSets.main.get().output + sourceSets.testFixtures.get().output
        runtimeClasspath += sourceSets.main.get().output + sourceSets.testFixtures.get().output
    }
}

configurations.named("liveTestImplementation") {
    extendsFrom(configurations.testImplementation.get())
}
configurations.named("liveTestRuntimeOnly") {
    extendsFrom(configurations.testRuntimeOnly.get())
}

lint {
    warningsAsErrors = true
    abortOnError = true
    lintConfig = rootProject.file("lint.xml")
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)

    testFixturesImplementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(testFixtures(project(":core")))
}

tasks.withType<Test>().configureEach {
    systemProperty("prompts.dir", promptsDir.asFile.absolutePath)
}

val apiKey: Provider<String> =
    providers
        .environmentVariable("ANTHROPIC_API_KEY")
        .orElse(
            providers
                .fileContents(rootProject.layout.projectDirectory.file("local.properties"))
                .asText
                .map { text ->
                    Properties().apply { load(text.reader()) }.getProperty("ANTHROPIC_API_KEY", "")
                },
        ).orElse("")

tasks.register<Test>("liveTest") {
    description = "Calls the real Anthropic API. Skipped when ANTHROPIC_API_KEY is not set."
    group = "verification"
    testClassesDirs = sourceSets["liveTest"].output.classesDirs
    classpath = sourceSets["liveTest"].runtimeClasspath
    val key = apiKey
    onlyIf("ANTHROPIC_API_KEY is set") { key.get().isNotBlank() }
    doFirst { environment("ANTHROPIC_API_KEY", key.get()) }
    outputs.upToDateWhen { false }
}
