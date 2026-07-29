import java.util.Properties

plugins {
    // AGP 9 ja traz o suporte a Kotlin embutido — aplicar o
    // 'org.jetbrains.kotlin.android' aqui e ERRO de build.
    id("com.android.application")
}

// Reaproveita o MESMO keystore de release do app mobile (pasta ../android).
// Assinar com a mesma chave nao e exigencia — o packageName e outro — mas
// mantem tudo do Hero Play sob uma assinatura so, e permite atualizar o app
// por cima nas TVs sem desinstalar.
val keystorePropertiesFile = rootProject.file("../android/key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.heroplay.tv"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.heroplay.tv"
        // Fire OS 5 (Fire Stick 2a geracao) roda Android 5.1 = API 22.
        minSdk = 22
        targetSdk = 36
        versionCode = 12
        versionName = "0.4.2"
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // No key.properties o caminho e relativo ao MODULO app do
                // projeto Flutter — por isso o "../android/app/".
                storeFile = rootProject.file("../android/app/" + keystoreProperties["storeFile"])
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    // ExoPlayer: abre MKV, HEVC, MPEG-TS e HLS — tudo o que o `<video>` do
    // WebView NAO abre. E o que faz o TV Box tocar o mesmo que a TV toca.
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("androidx.media3:media3-datasource:1.5.1")
}
