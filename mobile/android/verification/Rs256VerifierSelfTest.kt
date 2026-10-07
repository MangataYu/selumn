package cn.yooss.moodiary

import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.util.Base64

/** Plain JVM self-test; does not require Android, network access, or account tokens. */
fun main() {
    val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
    val publicKey = pair.public as RSAPublicKey
    val encoder = Base64.getUrlEncoder().withoutPadding()
    fun unsigned(value: BigInteger): String {
        val bytes = value.toByteArray()
        return encoder.encodeToString(if (bytes[0] == 0.toByte()) bytes.copyOfRange(1, bytes.size) else bytes)
    }
    val n = unsigned(publicKey.modulus)
    val e = unsigned(publicKey.publicExponent)
    val input = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0"
    val signature = Signature.getInstance("SHA256withRSA").run {
        initSign(pair.private)
        update(input.toByteArray(Charsets.US_ASCII))
        encoder.encodeToString(sign())
    }
    check(Rs256Verifier.verify(n, e, input, signature)) { "Valid signature rejected" }
    check(!Rs256Verifier.verify(n, e, "$input!", signature)) { "Modified payload accepted" }
    check(!Rs256Verifier.verify(n, e, input, signature.dropLast(2))) { "Truncated signature accepted" }
    check(!Rs256Verifier.verify(n, e, "中文", signature)) { "Non-ASCII input accepted" }
    check(!Rs256Verifier.verify("invalid*", e, input, signature)) { "Invalid JWK accepted" }
    check(!Rs256Verifier.verify(n, "AA", input, signature)) { "Zero exponent accepted" }
    check(!Rs256Verifier.verify(n, e, input, "")) { "Empty signature accepted" }
    val otherPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
    check(!Rs256Verifier.verify(unsigned((otherPair.public as RSAPublicKey).modulus), e, input, signature)) {
        "Signature accepted for a different key"
    }
    println("RS256 verification: 8 checks passed")
}
