#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef char *(*quill_wireguard_qt_import_config_callback)(
    const char *configuration,
    int existing_tunnel_count,
    const char *suggested_name
);

typedef void (*quill_wireguard_qt_free_string_callback)(char *string);

int quill_qt_run_interaction_smoke(int argc, char **argv);

int quill_enchanted_qt_run_app_json(
    int argc,
    char **argv,
    const char *payload_json
);

int quill_generic_qt_run_app_json(
    int argc,
    char **argv,
    const char *payload_json
);

int quill_wireguard_qt_run_wireguard_json(
    int argc,
    char **argv,
    const char *payload_json,
    quill_wireguard_qt_import_config_callback import_config,
    quill_wireguard_qt_free_string_callback free_string
);

#ifdef __cplusplus
}
#endif
