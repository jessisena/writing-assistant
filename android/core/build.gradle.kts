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

/** Reads [name] from the environment, else from `local.properties`, else "". */
fun liveKey(name: String): Provider<String> =
    providers
        .environmentVariable(name)
        .orElse(
            providers
                .fileContents(rootProject.layout.projectDirectory.file("local.properties"))
                .asText
                .map { text -> Properties().apply { load(text.reader()) }.getProperty(name, "") },
        ).orElse("")

val liveKeys: Map<String, Provider<String>> =
    listOf("ANTHROPIC_API_KEY", "GROQ_API_KEY").associateWith { liveKey(it) }

tasks.register<Test>("liveTest") {
    description =
        "Calls the real Anthropic and Groq APIs. Each provider's cases are skipped when its " +
        "key is not set, and the task is skipped when neither is."
    group = "verification"
    testClassesDirs = sourceSets["liveTest"].output.classesDirs
    classpath = sourceSets["liveTest"].runtimeClasspath
    val keys = liveKeys
    onlyIf("ANTHROPIC_API_KEY or GROQ_API_KEY is set") { keys.values.any { it.get().isNotBlank() } }
    doFirst { keys.forEach { (name, key) -> environment(name, key.get()) } }
    outputs.upToDateWhen { false }
}
