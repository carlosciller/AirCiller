#include "KeychainInteraction.h"
#include <Security/Security.h>

// AirCiller's existing credentials use the file-based login Keychain. Its
// process-local UI control has no equivalent in LAContext (data-protection
// Keychain). Isolate the legacy API in the test binary; never alter item ACLs.
int32_t ACPlaybackChecksDisableKeychainUI(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = SecKeychainSetUserInteractionAllowed(false);
    if (status != errSecSuccess) return status;
    Boolean allowed = true;
    status = SecKeychainGetUserInteractionAllowed(&allowed);
#pragma clang diagnostic pop
    if (status != errSecSuccess) return status;
    return allowed ? errSecInteractionNotAllowed : errSecSuccess;
}
