#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <xpc/xpc.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    xpc_connection_t connection = xpc_connection_create("local.carlosciller.AirCiller.CredentialService", NULL);
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) exit(1);
    });
    xpc_connection_activate(connection);
    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_string(request, "account", argv[1]);
    xpc_dictionary_set_string(request, "operation", "read");
    xpc_connection_send_message_with_reply(connection, request, dispatch_get_main_queue(), ^(xpc_object_t reply) {
        if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) exit(1);
        xpc_object_t status = xpc_dictionary_get_value(reply, "status");
        exit(status && xpc_get_type(status) == XPC_TYPE_INT64 && xpc_int64_get_value(status) == 0 ? 0 : 1);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(4); });
    dispatch_main();
}
