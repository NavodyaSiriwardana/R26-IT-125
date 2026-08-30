package com.example.frontend

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class YouTubeAccessibilityService : AccessibilityService() {

    companion object {
        var currentVideoTitle: String? = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return

        if (packageName == "com.google.android.youtube") {
            val rootNode = rootInActiveWindow ?: return
            val title = findVideoTitle(rootNode)
            if (title != null) {
                currentVideoTitle = title
            }
        }
    }

    private fun findVideoTitle(node: AccessibilityNodeInfo, depth: Int = 0): String? {
        if (depth > 15) return null

        val possibleIds = listOf(
            "com.google.android.youtube:id/title",
            "com.google.android.youtube:id/watch_metadata_title"
        )

        for (id in possibleIds) {
            val nodes = node.findAccessibilityNodeInfosByViewId(id)
            if (nodes.isNotEmpty()) {
                val text = nodes[0].text?.toString()
                if (!text.isNullOrBlank()) return text
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findVideoTitle(child, depth + 1)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    override fun onInterrupt() {}
}