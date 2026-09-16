package com.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ui.theme.MyApplicationTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    setContent {
      MyApplicationTheme {
        TelegramStorageScreen()
      }
    }
  }
}

data class ApiEndpointInfo(
  val method: String,
  val path: String,
  val description: String,
  val icon: ImageVector,
  val color: Color
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TelegramStorageScreen() {
  val endpoints = listOf(
    ApiEndpointInfo(
      method = "POST",
      path = "/api/files/upload",
      description = "Uploads file to Telegram channel via Bot API and stores metadata in PostgreSQL with Prisma.",
      icon = Icons.Default.CloudUpload,
      color = Color(0xFF2E7D32)
    ),
    ApiEndpointInfo(
      method = "GET",
      path = "/api/files/:id/download",
      description = "Fetches file path from Telegram getFile and streams directly to user with proper headers.",
      icon = Icons.Default.CloudDownload,
      color = Color(0xFF1565C0)
    ),
    ApiEndpointInfo(
      method = "GET",
      path = "/api/files",
      description = "Lists files and virtual folders with pagination support and parent_folder_id filtering.",
      icon = Icons.Default.Folder,
      color = Color(0xFFE65100)
    ),
    ApiEndpointInfo(
      method = "POST",
      path = "/api/folders",
      description = "Creates a virtual folder in PostgreSQL database without actual storage overhead.",
      icon = Icons.Default.CreateNewFolder,
      color = Color(0xFF6A1B9A)
    ),
    ApiEndpointInfo(
      method = "DELETE",
      path = "/api/files/:id",
      description = "Deletes Telegram message from channel via deleteMessage & removes DB record.",
      icon = Icons.Default.Delete,
      color = Color(0xFFC62828)
    )
  )

  Scaffold(
    topBar = {
      TopAppBar(
        title = {
          Text(
            text = "Telegram Cloud Backend",
            fontWeight = FontWeight.Bold
          )
        },
        colors = TopAppBarDefaults.topAppBarColors(
          containerColor = MaterialTheme.colorScheme.primaryContainer,
          titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
      )
    }
  ) { paddingValues ->
    LazyColumn(
      modifier = Modifier
        .fillMaxSize()
        .padding(paddingValues)
        .padding(16.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
      item {
        Card(
          colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
          shape = RoundedCornerShape(16.dp),
          modifier = Modifier.fillMaxWidth()
        ) {
          Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Box(
                modifier = Modifier
                  .size(40.dp)
                  .clip(CircleShape)
                  .background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center
              ) {
                Icon(
                  imageVector = Icons.Default.Storage,
                  contentDescription = null,
                  tint = MaterialTheme.colorScheme.onPrimary
                )
              }
              Spacer(modifier = Modifier.width(12.dp))
              Column {
                Text(
                  text = "Node.js + Express + TypeScript",
                  style = MaterialTheme.typography.titleMedium,
                  fontWeight = FontWeight.Bold
                )
                Text(
                  text = "Telegram Bot API + PostgreSQL Prisma",
                  style = MaterialTheme.typography.bodySmall,
                  color = MaterialTheme.colorScheme.onSurfaceVariant
                )
              }
            }
            Spacer(modifier = Modifier.height(12.dp))
            Text(
              text = "Backend architecture generated in /backend directory with full modular routing, services, controllers, and error handling.",
              style = MaterialTheme.typography.bodyMedium
            )
          }
        }
      }

      item {
        Text(
          text = "Implemented API Endpoints",
          style = MaterialTheme.typography.titleMedium,
          fontWeight = FontWeight.Bold,
          modifier = Modifier.padding(top = 8.dp)
        )
      }

      items(endpoints) { endpoint ->
        EndpointCard(endpoint = endpoint)
      }
    }
  }
}

@Composable
fun EndpointCard(endpoint: ApiEndpointInfo) {
  Card(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
  ) {
    Column(modifier = Modifier.padding(14.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Surface(
          shape = RoundedCornerShape(6.dp),
          color = endpoint.color.copy(alpha = 0.15f)
        ) {
          Text(
            text = endpoint.method,
            color = endpoint.color,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
          )
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text(
          text = endpoint.path,
          fontFamily = FontFamily.Monospace,
          fontWeight = FontWeight.SemiBold,
          fontSize = 13.sp,
          color = MaterialTheme.colorScheme.onSurface
        )
      }
      Spacer(modifier = Modifier.height(8.dp))
      Text(
        text = endpoint.description,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
      )
    }
  }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
  Text(text = "Hello $name!", modifier = modifier)
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
  MyApplicationTheme { Greeting("Android") }
}

