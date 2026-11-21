// phase-04
// JVM unit tests for the pure SMS admission gate. Runs for every
// build variant because SmsGate lives in the MAIN source set; the
// play-flavor acceptance rule (no SMS code reachable in play) is
// enforced by the receiver/manifest living only in src/power —
// verified by the phase static checks, not by this test.
package `in`.udao.app.capture

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsGateTest {

    // ---- sender gate: transactional passes -------------------------

    @Test
    fun `dashed operator senders pass`() {
        listOf(
            "VM-HDFCBK", "BX-ICICIB", "VM-SBI", "VM-AXISBK",
            "VM-BARDBKB", // 7-char tag — Bank of Baroda (wider than sketch)
            "VM-KOTAKB", "VM-PNBIND", "JD-PAYTM", "AD-SBIBNK",
        ).forEach {
            assertTrue("expected pass: $it", SmsGate.isTransactionalSender(it))
        }
    }

    @Test
    fun `plain institutional senders pass`() {
        listOf("HDFCBK", "PAYTM", "ICICIBANK").forEach {
            assertTrue("expected pass: $it", SmsGate.isTransactionalSender(it))
        }
    }

    @Test
    fun `sender is normalized before matching`() {
        assertTrue(SmsGate.isTransactionalSender(" vm-hdfcbk "))
        assertTrue(SmsGate.isTransactionalSender("vm-hdfcbk"))
        assertTrue(SmsGate.isTransactionalSender("\tVM-HDFCBK\n"))
    }

    // ---- sender gate: promo noise dies natively --------------------

    @Test
    fun `numeric promo senders are rejected`() {
        listOf("992030", "575757", "12345", "1234567890").forEach {
            assertFalse("expected reject: $it", SmsGate.isTransactionalSender(it))
        }
    }

    @Test
    fun `phones emails and junk are rejected`() {
        listOf(
            "+919999888877",
            "919876543210",
            "promo@offers.com",
            "VM-",
            "V-HDFCBK",
            "VM-HDFC1B2K3X4Y5Z6",
            "OFFERS",
            "ab",
            "",
        ).forEach {
            assertFalse("expected reject: $it", SmsGate.isTransactionalSender(it))
        }
    }

    @Test
    fun `null sender is rejected`() {
        assertFalse(SmsGate.isTransactionalSender(null))
    }

    // ---- WAL line shape ---------------------------------------------

    @Test
    fun `wal line maps sender into pkg with sms prefix`() {
        val line = SmsGate.walLine(" vm-hdfcbk ", "Rs.100 debited", 1730000000000L)
        val json = JSONObject(line)
        assertEquals("sms:VM-HDFCBK", json.getString("pkg"))
        assertEquals("Rs.100 debited", json.getString("text"))
        assertEquals(1730000000000L, json.getLong("ts"))
    }

    @Test
    fun `wal line nulls the notification-only fields`() {
        val json = JSONObject(SmsGate.walLine("VM-HDFCBK", "body", 1L))
        assertTrue(json.isNull("title"))
        assertTrue(json.isNull("bigText"))
        assertTrue(json.isNull("subText"))
        assertNull(json.opt("title"))
    }

    @Test
    fun `wal line survives bodies with quotes newlines and rupee signs`() {
        val body = "Debit ₹1,234.00 \"ac XX123\"\nUPI/RAZORPAY\\PAYMENT"
        val json = JSONObject(SmsGate.walLine("VM-ICICIB", body, 5L))
        assertEquals(body, json.getString("text"))
    }
}
