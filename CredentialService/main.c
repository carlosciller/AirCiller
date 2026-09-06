#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dispatch/dispatch.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xpc/xpc.h>

#ifndef AC_SIGNER_FINGERPRINT
#error A pinned signing certificate is required.
#endif

static const char *client_requirement =
    "certificate leaf = H\"" AC_SIGNER_FINGERPRINT "\" and "
    "(identifier \"local.carlosciller.AirCiller\" or "
    "identifier \"local.carlosciller.AirCiller.PlaybackChecks\") and "
    "info [ACCredentialServiceClientVersion] = \"1\"";
static dispatch_queue_t work_queue;
static unsigned long generation;

// The existing file-based login Keychain has no LAContext replacement for
// this process-local switch. It changes no Keychain ACL or global setting.
static OSStatus set_interaction(bool allowed) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return SecKeychainSetUserInteractionAllowed(allowed);
#pragma clang diagnostic pop
}

static bool safe_sender(xpc_object_t message) {
    SecCodeRef code = NULL;
    if (SecCodeCreateWithXPCMessage(message, kSecCSDefaultFlags, &code)) return false;
    CFDictionaryRef info = NULL;
    OSStatus status = SecCodeCopySigningInformation(code, kSecCSDynamicInformation | kSecCSSigningInformation, &info);
    CFRelease(code);
    if (status || !info) return false;
    uint32_t flags = 0;
    CFNumberRef value = CFDictionaryGetValue(info, kSecCodeInfoFlags);
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberSInt32Type, &flags);
    bool safe = (flags & kSecCodeSignatureRuntime) != 0;
    CFDictionaryRef entitlements = CFDictionaryGetValue(info, kSecCodeInfoEntitlementsDict);
    if (entitlements) {
        const CFStringRef forbidden[] = {
            CFSTR("com.apple.security.get-task-allow"),
            CFSTR("com.apple.security.cs.allow-dyld-environment-variables"),
        };
        for (unsigned i = 0; i < sizeof(forbidden) / sizeof(forbidden[0]); i++) {
            CFTypeRef flag = CFDictionaryGetValue(entitlements, forbidden[i]);
            if (flag && !CFEqual(flag, kCFBooleanFalse)) safe = false;
        }
    }
    CFRelease(info);
    return safe;
}

static OSStatus read_credential(const char *account_text, CFDataRef *data, bool cleanup) {
    CFStringRef account = CFStringCreateWithCString(NULL, account_text, kCFStringEncodingUTF8);
    if (!account) return errSecParam;
#ifdef AC_CREDENTIAL_FIXTURE
    const CFStringRef service = CFSTR("local.carlosciller.AirCiller.CredentialService.Probe");
#else
    const CFStringRef service = CFSTR("local.carlosciller.AirCiller.AirPlay");
    if (cleanup) { CFRelease(account); return errSecParam; }
#endif
    const void *keys[] = {kSecClass, kSecAttrService, kSecAttrAccount};
    const void *values[] = {kSecClassGenericPassword, service, account};
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (unsigned i = 0; i < 3; i++) CFDictionarySetValue(query, keys[i], values[i]);
#ifdef AC_CREDENTIAL_FIXTURE
    if (cleanup) {
        OSStatus status = SecItemDelete(query);
        CFRelease(query); CFRelease(account);
        return status;
    }
    // Test builds alone can create a synthetic item in a separate service.
    static const char fixture[] = "AirCiller synthetic credential";
    CFDataRef fake = CFDataCreate(NULL, (const UInt8 *)fixture, sizeof(fixture) - 1);
    CFDictionarySetValue(query, kSecValueData, fake);
    OSStatus add_status = SecItemAdd(query, NULL);
    CFRelease(fake);
    CFDictionaryRemoveValue(query, kSecValueData);
    if (add_status != errSecSuccess && add_status != errSecDuplicateItem) {
        CFRelease(query); CFRelease(account); return add_status;
    }
#endif
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result);
    if (!status && result && CFGetTypeID(result) == CFDataGetTypeID() && CFDataGetLength(result) <= 16384) {
        *data = (CFDataRef)result;
    } else {
        if (result) CFRelease(result);
        if (!status) status = errSecDecode;
    }
    CFRelease(query); CFRelease(account);
    return status;
}

static void handle_request(xpc_connection_t peer, xpc_object_t message) {
    if (xpc_get_type(message) != XPC_TYPE_DICTIONARY) return;
    unsigned long current_generation = ++generation;
    xpc_object_t reply = xpc_dictionary_create_reply(message);
    if (!reply) return;
    OSStatus status = errSecAuthFailed;
    CFDataRef data = NULL;
    const char *account = xpc_dictionary_get_string(message, "account");
    const char *operation = xpc_dictionary_get_string(message, "operation");
    bool cleanup = operation && !strcmp(operation, "cleanupFixture");
    if (xpc_dictionary_get_int64(message, "version") == 1 && account && *account && strlen(account) <= 256
        && operation && (!strcmp(operation, "read") || cleanup)
        && xpc_connection_get_euid(peer) == geteuid() && safe_sender(message)) {
        status = set_interaction(xpc_dictionary_get_bool(message, "allowInteraction"));
        if (!status) status = read_credential(account, &data, cleanup);
        if (set_interaction(false) != errSecSuccess) _exit(1);
    }
    xpc_dictionary_set_int64(reply, "status", status);
    if (data) {
        xpc_dictionary_set_data(reply, "credential", CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
        CFRelease(data);
    }
    xpc_connection_send_message(peer, reply);
    xpc_release(reply);
    // No launch agent, network listener or idle background process.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), work_queue, ^{
        if (generation == current_generation) _exit(0);
    });
}

static void accept_connection(xpc_connection_t peer) {
    if (xpc_connection_set_peer_code_signing_requirement(peer, client_requirement)) {
        xpc_connection_cancel(peer); return;
    }
    xpc_connection_set_target_queue(peer, work_queue);
    xpc_connection_set_event_handler(peer, ^(xpc_object_t message) { handle_request(peer, message); });
    xpc_connection_activate(peer);
}

int main(void) {
    if (set_interaction(false) != errSecSuccess) return 1;
    work_queue = dispatch_queue_create("local.carlosciller.AirCiller.CredentialService", DISPATCH_QUEUE_SERIAL);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), work_queue, ^{
        if (!generation) _exit(0);
    });
    // A stalled authorization dialog cannot leave an orphan service indefinitely.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 75 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ _exit(1); });
    xpc_main(accept_connection);
}
