package `in`.meshsetu.protocol

import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.TrafficClass
import kotlin.test.Test
import kotlin.test.assertEquals

class SchedulerTest {
    @Test fun emergencyPreemptsBulkAndExpiryIsDropped() {
        val q = OutboundScheduler()
        q.enqueue(EncryptedObject(1u, TrafficClass.VOICE_EVIDENCE, byteArrayOf(1), 100), 0)
        q.enqueue(EncryptedObject(2u, TrafficClass.SOS_STRUCTURED, byteArrayOf(1), 100), 0)
        q.enqueue(EncryptedObject(3u, TrafficClass.ROOM_MESSAGE, byteArrayOf(1), 1), 0)
        assertEquals(2u, q.next(0)?.objectId)
        assertEquals(1u, q.next(2)?.objectId)
    }
}

