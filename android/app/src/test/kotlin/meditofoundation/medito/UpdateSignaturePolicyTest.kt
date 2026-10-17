package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test

class UpdateSignaturePolicyTest {
    private val cert = "meditejo test certificate".toByteArray()
    private val certDigest = UpdateSignaturePolicy.sha256Hex(cert)

    @Test fun digestIsLowerCaseHexSha256() {
        // SHA-256 of the empty input.
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            UpdateSignaturePolicy.sha256Hex(ByteArray(0)),
        )
    }

    @Test fun oneSignerWithThePinnedCertificateMatches() {
        assertTrue(UpdateSignaturePolicy.signersMatchPin(listOf(cert), certDigest))
    }

    @Test fun pinsWrittenWithColonsAndUpperCaseStillMatch() {
        val formatted = certDigest.uppercase().chunked(2).joinToString(":")
        assertTrue(UpdateSignaturePolicy.signersMatchPin(listOf(cert), formatted))
    }

    @Test fun aDifferentCertificateIsRefused() {
        assertFalse(UpdateSignaturePolicy.signersMatchPin(listOf("someone else".toByteArray()), certDigest))
    }

    @Test fun noSignersIsRefused() {
        assertFalse(UpdateSignaturePolicy.signersMatchPin(emptyList(), certDigest))
    }

    @Test fun severalSignersAreRefusedEvenWhenOneMatches() {
        assertFalse(UpdateSignaturePolicy.signersMatchPin(listOf(cert, "another".toByteArray()), certDigest))
    }

    @Test fun aTruncatedPinIsRefused() {
        assertFalse(UpdateSignaturePolicy.signersMatchPin(listOf(cert), certDigest.take(32)))
    }

    @Test fun theBuiltInPinIsTheDocumentedDigest() {
        assertEquals(
            "07:87:EC:F8:50:D8:DF:93:F9:02:DB:09:A9:8D:C6:1E:9C:E4:0F:E1:39:BF:54:35:A5:35:A6:2E:18:5A:50:31",
            UpdateSignaturePolicy.PINNED_SHA256.uppercase().chunked(2).joinToString(":"),
        )
        assertEquals(64, UpdateSignaturePolicy.PINNED_SHA256.length)
    }
}
