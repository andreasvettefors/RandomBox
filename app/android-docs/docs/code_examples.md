# Code examples

## Sample code to getting started

```` kotlin
abstract class TextFormattingStrategy {
    abstract fun format(text: String): String
}


class UnderlineStrategy : TextFormattingStrategy() {
    override fun format(text: String): String {
        return "<u>$text</u>"
    }
}

class BoldStrategy : TextFormattingStrategy() {
    override fun format(text: String): String {
        return "<strong>$text</strong>"
    }
}

class ItalicStrategy : TextFormattingStrategy() {
	// You can use this syntax too
    override fun format(text: String): String = "<i>$text</i>" 
}

fun format(text: String, strategy: TextFormattingStrategy): String {
    return strategy.format(text)
}

val text = "Awesome text !"
````
