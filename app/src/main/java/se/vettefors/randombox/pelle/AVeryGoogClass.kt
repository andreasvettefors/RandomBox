package se.vettefors.randombox.pelle

private data class AVeryGoogClass(val id: String, val username: String)

data class Hello internal constructor(
    internal val isFocused: Boolean
) {
    fun makeFocused() {

    }
}
