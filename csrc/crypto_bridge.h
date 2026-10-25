#ifndef CRYPTO_BRIDGE_H
#define CRYPTO_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GS_KEY_SIZE 32
#define GS_NONCE_SIZE 12
#define GS_TAG_SIZE 16

int gs_crypto_generate_key(uint8_t *out_key);
int gs_crypto_encrypt(const uint8_t *key, const uint8_t *plaintext, int64_t plaintext_len, uint8_t **out_ciphertext, int64_t *out_len);
int gs_crypto_decrypt(const uint8_t *key, const uint8_t *ciphertext, int64_t ciphertext_len, uint8_t **out_plaintext, int64_t *out_len);
void gs_crypto_free(void *ptr);

void gs_crypto_sha256(const uint8_t *data, int64_t len, uint8_t *out_hash_32);
int gs_crypto_base32_encode(const uint8_t *data, int64_t len, char **out_str);

#ifdef __cplusplus
}
#endif

#endif /* CRYPTO_BRIDGE_H */
