package meditofoundation.medito

import java.security.MessageDigest

/**
 * Which signing certificate an update must carry.
 *
 * The pin is the SHA-256 of Meditejo's durable release certificate (see
 * docs/fork/BUILD.md). It is the same digest tools/meditejo/build_apk.sh checks
 * before and after signing. Android would refuse an APK signed by another key at
 * install time; checking first lets the app say so plainly and hand nothing to
 * the installer.
 */
object UpdateSignaturePolicy {
    const val PINNED_SHA256 =
        "0787ecf850d8df93f902db09a98dc61e9ce40fe139bf5435a535a62e185a5031"

    /** Lower-case hex SHA-256 of [bytes], e.g. a DER-encoded certificate. */
    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    /** Hex digest without colons, spaces or case, so `07:87:EC…` compares equal. */
    fun normalize(digest: String): String =
        digest.filter { it != ':' && !it.isWhitespace() }.lowercase()

    /**
     * True only for exactly one signer whose certificate digest is [pinned].
     * No signers, several signers, or a different certificate all fail.
     */
    fun signersMatchPin(signerCertificates: List<ByteArray>, pinned: String = PINNED_SHA256): Boolean {
        if (signerCertificates.size != 1) return false
        val actual = sha256Hex(signerCertificates[0])
        return MessageDigest.isEqual(actual.toByteArray(), normalize(pinned).toByteArray())
    }
}
