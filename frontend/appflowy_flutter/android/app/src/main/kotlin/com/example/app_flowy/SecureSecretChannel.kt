package io.appflowy.appflowy

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hardware-backed secret storage on Android (`appflowy/secure_store`), sealing
 * OAuth tokens, the AppFlowy password, and sync vault keys with an
 * AndroidKeyStore AES-256-GCM master key so background sync and app restarts
 * never require re-authenticating.
 */
class SecureSecretChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    )
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "store" -> {
                    val scope = call.argument<String>("scope") ?: ""
                    val id = call.argument<String>("id") ?: ""
                    val secret = call.argument<String>("secret") ?: ""
                    if (scope.isEmpty() || id.isEmpty()) {
                        result.error("invalid-args", "scope and id are required", null)
                        return
                    }
                    storeSecret(scope, id, secret)
                    result.success(null)
                }
                "lookup" -> {
                    val scope = call.argument<String>("scope") ?: ""
                    val id = call.argument<String>("id") ?: ""
                    if (scope.isEmpty() || id.isEmpty()) {
                        result.success(null)
                        return
                    }
                    result.success(lookupSecret(scope, id))
                }
                "clear" -> {
                    val scope = call.argument<String>("scope") ?: ""
                    val id = call.argument<String>("id") ?: ""
                    if (scope.isNotEmpty() && id.isNotEmpty()) {
                        prefs.edit().remove(entryKey(scope, id)).apply()
                    }
                    result.success(null)
                }
                "clearAll" -> {
                    prefs.edit().clear().apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("keystore-error", error.message ?: "Android Keystore error", null)
        }
    }

    private fun entryKey(scope: String, id: String): String = "$scope:$id"

    @Synchronized
    private fun getOrCreateMasterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun storeSecret(scope: String, id: String, secret: String) {
        val key = entryKey(scope, id)
        if (secret.isEmpty()) {
            prefs.edit().remove(key).apply()
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateMasterKey())
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val sealed = cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
        val ivEncoded = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val dataEncoded = Base64.encodeToString(sealed, Base64.NO_WRAP)
        prefs.edit().putString(key, "$ivEncoded:$dataEncoded").apply()
    }

    private fun lookupSecret(scope: String, id: String): String? {
        val key = entryKey(scope, id)
        val raw = prefs.getString(key, null) ?: return null
        val separator = raw.indexOf(':')
        if (separator <= 0) {
            return null
        }
        return try {
            val iv = Base64.decode(raw.substring(0, separator), Base64.NO_WRAP)
            val sealed = Base64.decode(raw.substring(separator + 1), Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateMasterKey(),
                GCMParameterSpec(128, iv),
            )
            cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(sealed), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "appflowy/secure_store"
        private const val PREFS_NAME = "appflowy_secure_secrets"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "io.appflowy.secure_store.master_key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
