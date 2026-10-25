// Cryptography and hashing helpers
namespace crypto;

import std;

extern fn crypt_gen_key_c(out_key: u8[>..]&) -> i32 = "gs_crypt_gen_key";
extern fn crypt_encrypt_c(key: const u8[:], plaintext: const u8[:], out_cipher: u8[>..]&) -> i32 = "gs_crypt_encrypt";
extern fn crypt_decrypt_c(key: const u8[:], ciphertext: const u8[:], out_plain: u8[>..]&) -> i32 = "gs_crypt_decrypt";
extern fn crypt_sha256_c(data: const u8[:], out_hash_hex: u8[>..]&) -> i32 = "gs_crypt_sha256";
extern fn crypt_base32_c(data: const u8[:], out_b32: u8[>..]&) -> i32 = "gs_crypt_base32";

fn generate_key() -> u8[>..] {
    var out: u8[>..] = [];
    crypt_gen_key_c(out);
    return out;
}

fn encrypt(key: const u8[:], plaintext: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if key.len == 0 {
        out.append(plaintext);
        return out;
    }
    var rc = crypt_encrypt_c(key, plaintext, out);
    if rc != 0 {
        var empty: u8[>..] = [];
        return empty;
    }
    return out;
}

fn decrypt(key: const u8[:], ciphertext: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if key.len == 0 {
        out.append(ciphertext);
        return out;
    }
    var rc = crypt_decrypt_c(key, ciphertext, out);
    if rc != 0 {
        var empty: u8[>..] = [];
        return empty;
    }
    return out;
}

fn sha256(data: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    crypt_sha256_c(data, out);
    return out;
}

fn base32_encode(data: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    crypt_base32_c(data, out);
    return out;
}
