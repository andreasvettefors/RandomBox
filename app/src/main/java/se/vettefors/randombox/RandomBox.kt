package se.vettefors.randombox

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlin.random.Random


/**
 * A box that will change background to a random color when pressing the button
 */
@Composable
fun RandomBox(message: String) {
    var color by remember {
        mutableStateOf(Color.Blue)
    }

    Box(modifier = Modifier
        .fillMaxSize()
        .background(color), contentAlignment = Alignment.Center) {

        Text(text = message)
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = {
            color = Color(
                Random.nextFloat(),
                Random.nextFloat(),
                Random.nextFloat(),
                1f
            )
        }) {
            Text("Change background color")
        }
    }
}