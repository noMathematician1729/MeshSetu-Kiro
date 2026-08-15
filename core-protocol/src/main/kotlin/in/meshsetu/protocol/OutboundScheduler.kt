package `in`.meshsetu.protocol

import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.TrafficClass
import java.util.PriorityQueue

class OutboundScheduler {
    private val queue = PriorityQueue<EncryptedObject>(compareBy<EncryptedObject> { it.trafficClass.rank }.thenBy { it.createdAtMs }.thenBy { it.objectId })

    @Synchronized fun enqueue(value: EncryptedObject, nowMs: Long) {
        require(value.bytes.isNotEmpty())
        if (value.expiresAtMs > nowMs) queue += value
    }

    @Synchronized fun next(nowMs: Long): EncryptedObject? {
        while (queue.peek()?.expiresAtMs?.let { it <= nowMs } == true) queue.remove()
        return queue.poll()
    }

    @Synchronized fun size(): Int = queue.size
}

class RecentObjectCache(private val maxEntries: Int = 4096) {
    private val seen = object : LinkedHashMap<ULong, Long>(maxEntries, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<ULong, Long>?): Boolean = size > maxEntries
    }

    @Synchronized fun markIfNew(id: ULong, expiresAtMs: Long, nowMs: Long): Boolean {
        seen.entries.removeIf { it.value <= nowMs }
        if (seen.containsKey(id)) return false
        seen[id] = expiresAtMs
        return true
    }
}
