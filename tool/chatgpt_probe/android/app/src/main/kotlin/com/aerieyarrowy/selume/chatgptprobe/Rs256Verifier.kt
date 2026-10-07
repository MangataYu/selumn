package com.aerieyarrowy.selume.chatgptprobe

import java.math.BigInteger
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.RSAPublicKeySpec
import java.util.Base64

/** RS256 verification only; JWT claims and trusted issuer checks belong to Dart. */
object Rs256Verifier {
    private val base64Url = Regex("^[A-Za-z0-9_-]+$")

    fun verify(n: String, e: String, input: String, signature: String): Boolean = try {
        require(n.length <= 1366 && e.length <= 16 && signature.length <= 1366)
        require(input.isNotEmpty() && input.length <= 262144)
        require(input.all { it.code <= 127 })
        val modulus = BigInteger(1, decode(n))
        val exponent = BigInteger(1, decode(e))
        require(modulus.bitLength() in 2048..8192)
        require(exponent >= BigInteger.valueOf(3) && exponent.testBit(0))
        val signatureBytes = decode(signature)
        require(signatureBytes.size == (modulus.bitLength() + 7) / 8)
        val publicKey = KeyFactory.getInstance("RSA").generatePublic(
            RSAPublicKeySpec(modulus, exponent),
        )
        Signature.getInstance("SHA256withRSA").run {
            initVerify(publicKey)
            update(input.toByteArray(Charsets.US_ASCII))
            verify(signatureBytes)
        }
    } catch (_: Exception) {
        false
    }

    private fun decode(value: String): ByteArray {
        require(base64Url.matches(value))
        return Base64.getUrlDecoder().decode(value)
    }
}
