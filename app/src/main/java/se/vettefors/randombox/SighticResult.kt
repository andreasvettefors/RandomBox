package se.vettefors.randombox

sealed class SighticResult<out T> {
    data class Success<T>(val value: T) : SighticResult<T>()

    data class Failure(val error: Boolean) : SighticResult<Nothing>()
}