plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.dokka)
    alias(libs.plugins.compose.compiler)
    id("maven-publish")
}

val libraryVersion = "1.0.0"

android {
    namespace = "Api"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }
}

dokka {
    dokkaSourceSets.main {

        /*perPackageOption {
// Match all packages and suppress them
            matchingRegex.set("(.*?)")
            suppress.set(true)
        }*/

        perPackageOption {
// Match all packages and suppress them
            matchingRegex.set("(\\S*randombox.\\S*)")
            suppress.set(false)
        }

        // contains descriptions for the module and the packages
    }

}


afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("maven") {
                groupId = "se.vettefors"
                artifactId = "randombox"
                version = "0.1.0"

                pom {
                    name.set("$groupId:$artifactId")
                    this.description.set("A random box")

                    licenses {
                        license {
                            name.set("The Apache License, Version 2.0")
                            url.set("http://www.apache.org/licenses/LICENSE-2.0.txt")
                        }
                    }

                    developers {
                        developer {
                            name.set("A Random box")
                            email.set("randomvox@randombox.com")
                            organization.set("Random box")
                            organizationUrl.set("https://www.randombox.com/")
                        }
                    }

                }

                from(project.components["release"])
            }
        }
    }

}

dependencies {

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
}

tasks.register("getLibraryVersion") {
    println(libraryVersion)
}