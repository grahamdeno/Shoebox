/*
 * Apple Root CA - G3, the certificate every StoreKit purchase chain ends in, as base64 of its DER bytes.
 *
 * NOT FILLED IN YET. Until it is, no purchase verifies (the Plus gate fails closed: nobody can get an address).
 * Fill it from Apple's own file and check the fingerprint against the one Apple publishes:
 *   https://www.apple.com/certificateauthority/  (Apple Root CA - G3, AppleRootCA-G3.cer)
 *   base64 -i AppleRootCA-G3.cer | tr -d '\n'
 *   openssl x509 -inform DER -in AppleRootCA-G3.cer -noout -subject -fingerprint -sha256
 * docs/handoff/grok-identity-build.md has the steps and the check. relay/app/test/purchase.test.mjs fails if what is
 * pasted here is not a self-signed Apple Root CA - G3.
 */
export const APPLE_ROOT_CA_G3_B64 = "";
