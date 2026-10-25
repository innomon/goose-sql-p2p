#include "crypto_bridge.h"
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <stdlib.h>
#include <string.h>

int gs_crypto_generate_key(uint8_t *out_key) {
    if (!out_key) return -1;
    if (RAND_bytes(out_key, GS_KEY_SIZE) != 1) return -1;
    return 0;
}

int gs_crypto_encrypt(const uint8_t *key, const uint8_t *plaintext, int64_t plaintext_len, uint8_t **out_ciphertext, int64_t *out_len) {
    if (!key || !out_ciphertext || !out_len) return -1;
    if (plaintext_len < 0) return -1;

    uint8_t nonce[GS_NONCE_SIZE];
    if (RAND_bytes(nonce, GS_NONCE_SIZE) != 1) return -1;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GS_NONCE_SIZE, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    int64_t total_alloc = GS_NONCE_SIZE + plaintext_len + GS_TAG_SIZE;
    uint8_t *out = (uint8_t *)malloc(total_alloc > 0 ? total_alloc : 1);
    if (!out) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    memcpy(out, nonce, GS_NONCE_SIZE);

    int outlen = 0;
    if (plaintext_len > 0) {
        if (EVP_EncryptUpdate(ctx, out + GS_NONCE_SIZE, &outlen, plaintext, (int)plaintext_len) != 1) {
            free(out);
            EVP_CIPHER_CTX_free(ctx);
            return -1;
        }
    }

    int final_len = 0;
    if (EVP_EncryptFinal_ex(ctx, out + GS_NONCE_SIZE + outlen, &final_len) != 1) {
        free(out);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    uint8_t tag[GS_TAG_SIZE];
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, GS_TAG_SIZE, tag) != 1) {
        free(out);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    memcpy(out + GS_NONCE_SIZE + outlen + final_len, tag, GS_TAG_SIZE);

    EVP_CIPHER_CTX_free(ctx);

    *out_ciphertext = out;
    *out_len = GS_NONCE_SIZE + outlen + final_len + GS_TAG_SIZE;
    return 0;
}

int gs_crypto_decrypt(const uint8_t *key, const uint8_t *ciphertext, int64_t ciphertext_len, uint8_t **out_plaintext, int64_t *out_len) {
    if (!key || !ciphertext || !out_plaintext || !out_len) return -1;
    if (ciphertext_len < GS_NONCE_SIZE + GS_TAG_SIZE) return -1;

    const uint8_t *nonce = ciphertext;
    int64_t payload_len = ciphertext_len - GS_NONCE_SIZE - GS_TAG_SIZE;
    const uint8_t *encrypted_data = ciphertext + GS_NONCE_SIZE;
    const uint8_t *tag = ciphertext + ciphertext_len - GS_TAG_SIZE;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GS_NONCE_SIZE, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    uint8_t *out = (uint8_t *)malloc(payload_len > 0 ? payload_len + 1 : 1);
    if (!out) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    int outlen = 0;
    if (payload_len > 0) {
        if (EVP_DecryptUpdate(ctx, out, &outlen, encrypted_data, (int)payload_len) != 1) {
            free(out);
            EVP_CIPHER_CTX_free(ctx);
            return -1;
        }
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, GS_TAG_SIZE, (void *)tag) != 1) {
        free(out);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    int final_len = 0;
    if (EVP_DecryptFinal_ex(ctx, out + outlen, &final_len) <= 0) {
        free(out);
        EVP_CIPHER_CTX_free(ctx);
        return -1; // Auth verification failed
    }

    EVP_CIPHER_CTX_free(ctx);

    int64_t plain_total = outlen + final_len;
    out[plain_total] = '\0';
    *out_plaintext = out;
    *out_len = plain_total;
    return 0;
}

void gs_crypto_free(void *ptr) {
    if (ptr) free(ptr);
}

void gs_crypto_sha256(const uint8_t *data, int64_t len, uint8_t *out_hash_32) {
    if (!out_hash_32) return;
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    if (data && len > 0) {
        SHA256_Update(&ctx, data, (size_t)len);
    }
    SHA256_Final(out_hash_32, &ctx);
}

static const char base32_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

int gs_crypto_base32_encode(const uint8_t *data, int64_t len, char **out_str) {
    if (!data || len <= 0 || !out_str) return -1;
    int64_t out_len = ((len + 4) / 5) * 8;
    char *res = (char *)malloc(out_len + 1);
    if (!res) return -1;

    int64_t r_idx = 0;
    int64_t i = 0;
    while (i < len) {
        uint64_t buf = 0;
        int count = 0;
        for (int b = 0; b < 5; b++) {
            buf <<= 8;
            if (i + b < len) {
                buf |= (data[i + b] & 0xFF);
                count++;
            }
        }
        int bits = count * 8;
        int pad = (5 - count);
        buf <<= (pad * 8);

        for (int s = 0; s < 8; s++) {
            if (s * 5 < bits) {
                int shift = 35 - s * 5;
                int idx = (int)((buf >> shift) & 0x1F);
                res[r_idx++] = base32_chars[idx];
            } else {
                res[r_idx++] = '=';
            }
        }
        i += 5;
    }
    res[r_idx] = '\0';
    *out_str = res;
    return 0;
}
