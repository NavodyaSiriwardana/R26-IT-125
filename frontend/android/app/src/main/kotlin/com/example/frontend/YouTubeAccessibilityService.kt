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

    // YouTube renames its internal view IDs across app updates, so the
    // exact IDs below go stale periodically (title/watch_metadata_title
    // are known to have disappeared already). Try them first as a cheap
    // fast path, then fall back to the container ID that has stayed
    // stable across versions (video_metadata_layout) and take the first
    // text/content-description found inside it — the title row is always
    // the first thing in that container, ahead of channel/view-count rows.
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

        val metadataNodes = node.findAccessibilityNodeInfosByViewId(
            "com.google.android.youtube:id/video_metadata_layout"
        )
        if (metadataNodes.isNotEmpty()) {
            val text = findFirstTextOrDescription(metadataNodes[0])
            if (!text.isNullOrBlank()) return text
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findVideoTitle(child, depth + 1)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    private fun findFirstTextOrDescription(node: AccessibilityNodeInfo, depth: Int = 0): String? {
        if (depth > 10) return null

        val text = node.text?.toString()
        if (!text.isNullOrBlank()) return text

        val description = node.contentDescription?.toString()
        if (!description.isNullOrBlank()) return description

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findFirstTextOrDescription(child, depth + 1)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    override fun onInterrupt() {}
}