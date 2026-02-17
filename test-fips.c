#include <stdio.h>
#include <string.h>
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/settings.h>
#include <wolfssl/wolfcrypt/random.h>
#include <wolfssl/wolfcrypt/fips_test.h>
#include <wolfssl/wolfcrypt/sha256.h>
#include <wolfssl/wolfcrypt/error-crypt.h>

int main(void)
{
    int ret;
    wc_Sha256 sha;
    byte hash[WC_SHA256_DIGEST_SIZE];
    const char* data = "abc";

    /* Expected SHA256 hash of "abc" */
    const byte expected_hash[WC_SHA256_DIGEST_SIZE] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };

    printf("Testing wolfSSL FIPS installation...\n");

    #ifdef HAVE_FIPS
        printf("FIPS mode: ENABLED\n");
        #ifdef HAVE_FIPS_VERSION
            printf("FIPS version: %d\n", HAVE_FIPS_VERSION);
        #else
            printf("FIPS version: Enabled (version macro not available)\n");
        #endif
    #else
        printf("FIPS mode: DISABLED (WARNING!)\n");
    #endif

    printf("\nRunning FIPS CAST (Known Answer Tests)...\n");
    wc_SetSeed_Cb(wc_GenerateSeed);
    ret = wc_RunAllCast_fips();
    if (ret != 0) {
        printf("FIPS CAST failed: %d\n", ret);
        return 1;
    }
    printf("FIPS CAST: PASSED\n");

    printf("\nRunning SHA256 test...\n");
    ret = wc_InitSha256(&sha);
    if (ret != 0) {
        printf("SHA256 Init failed: %d\n", ret);
        return 1;
    }

    ret = wc_Sha256Update(&sha, (const byte*)data, 3);
    if (ret != 0) {
        printf("SHA256 Update failed: %d\n", ret);
        return 1;
    }

    ret = wc_Sha256Final(&sha, hash);
    if (ret != 0) {
        printf("SHA256 Final failed: %d\n", ret);
        return 1;
    }

    printf("SHA256('abc') = ");
    for (int i = 0; i < WC_SHA256_DIGEST_SIZE; i++) {
        printf("%02x", hash[i]);
    }
    printf("\n");

    printf("Expected:       ");
    for (int i = 0; i < WC_SHA256_DIGEST_SIZE; i++) {
        printf("%02x", expected_hash[i]);
    }
    printf("\n");

    /* Compare computed hash with expected hash */
    if (memcmp(hash, expected_hash, WC_SHA256_DIGEST_SIZE) != 0) {
        printf("\n✗ SHA256 hash mismatch! FIPS cryptography is not working correctly.\n");
        return 1;
    }
    printf("SHA256 hash matches expected value ✓\n");

    printf("\nwolfSSL FIPS test: ALL PASSED ✓\n");

    return 0;
}
