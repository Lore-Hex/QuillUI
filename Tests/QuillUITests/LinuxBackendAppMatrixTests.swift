import Foundation
import Testing

@Suite("Linux backend app matrix")
struct LinuxBackendAppMatrixTests {
    private static let expectedAppProducts = [
        "quill-enchanted",
        "quill-enchanted-upstream-slice",
        "quill-icecubes",
        "quill-netnewswire",
        "quill-codeedit",
        "quill-signal",
        "quill-telegram",
        "quill-iina",
        "quill-wireguard",
        "quill-wireguard-qt"
    ]

    private static let expectedSmokeProducts = [
        "quill-gtk-interaction-smoke",
        "quill-qt-interaction-smoke"
    ]

    private static let expectedGeneratedAppProducts = [
        "quill-chat-linux"
    ]

    private static let profileCSVHeader = "product,requested_backend,runtime_backend,runtime_mode,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"

    private static var expectedAppMatrix: [String] {
        expectedAppProducts.flatMap { product in
            switch product {
            case "quill-wireguard":
                ["quill-wireguard\tgtk"]
            case "quill-wireguard-qt":
                ["quill-wireguard-qt\tqt"]
            default:
                ["\(product)\tgtk", "\(product)\tqt"]
            }
        }
    }

    private static var expectedAppBuildPlan: [String] {
        expectedAppProducts.map { product in
            "\(product)\t\(product == "quill-wireguard-qt" ? "qt" : "gtk")"
        }
    }

    private static func expectedRuntimeBackend(product: String, backend: String) -> String {
        product == "quill-wireguard-qt" && backend == "qt" ? "qt" : "gtk"
    }

    private static func expectedRuntimeMode(product: String, backend: String) -> String {
        expectedRuntimeBackend(product: product, backend: backend) == backend ? "native" : "platformFallback"
    }

    @Test("covers each user-facing app product once")
    func coversEachUserFacingAppProductOnce() throws {
        let root = try packageRoot()
        let matrixScript = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let legacyMatrixScript = root.appendingPathComponent("scripts/linux-gtk-app-products.sh")

        let result = try runScript(matrixScript, arguments: ["backend-apps"])
        #expect(result.status == 0, Comment(rawValue: result.output))
        let gtkResult = try runScript(matrixScript, arguments: ["gtk-apps"])
        #expect(gtkResult.status == 0, Comment(rawValue: gtkResult.output))
        #expect(gtkResult.output == result.output)
        let legacyResult = try runScript(legacyMatrixScript)
        #expect(legacyResult.status == 0, Comment(rawValue: legacyResult.output))
        #expect(legacyResult.output == result.output)

        let products = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        #expect(products == Self.expectedAppProducts)
        #expect(Set(products).count == products.count)

        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        for product in products {
            #expect(manifest.contains(".executable(name: \"\(product)\""))
        }

        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("Build native backend app products"))
        #expect(workflow.contains("Validate backend product matrix"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh validate-integrity"))
        #expect(workflow.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux fixed-app-backends"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products visual generated-app-matrix '.qa/{product}-generated-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh visual smoke-matrix '.qa/{product}-visual-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products interaction smoke-interaction-matrix '.qa/{product}-{mode}-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction generated-app-matrix '.qa/{product}-toolbar-menu-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products visual app-matrix '.qa/{product}-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction interaction-matrix '.qa/{product}-interaction-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction interaction-extra-mode-matrix '.qa/{product}-{mode}-{backend}.png'"))
        #expect(workflow.contains("native Qt products such as quill-wireguard-qt"))
        #expect(!workflow.contains("Qt rows currently exercise the shared launch-plan fallback"))
        #expect(!workflow.contains("With no per-product branch in `verify-backend-screenshot.py`"))
        #expect(workflow.contains("Generated Enchanted backend visual smokes"))
        #expect(workflow.contains("Generated Enchanted toolbar interaction smokes"))
        #expect(workflow.contains("Quill app backend interaction smokes"))
        #expect(workflow.contains("backend-renders end-to-end"))
        #expect(workflow.contains("qt6-base-dev"))
        #expect(!workflow.contains("GTK-renders end-to-end"))
        #expect(workflow.contains("Backend launch target interaction smokes"))
        #expect(!workflow.contains("built_products=\" \""))
        #expect(!workflow.contains("while IFS=\"$tab\" read -r product backend; do"))
        #expect(workflow.contains("scripts/run-linux-backend-profile-csv.sh --matrix profile-matrix /tmp/quillui-profile.csv"))
        #expect(!workflow.contains("scripts/quillui-backend-products.sh profile-matrix | scripts/run-linux-backend-profile-csv.sh"))
        #expect(workflow.contains("scripts/check-linux-backend-profile-budget.sh /tmp/quillui-profile.csv"))
        #expect(workflow.contains("--require-backend-matrix"))
        #expect(workflow.contains("name: Swift Linux Backends"))
        #expect(workflow.contains("swift-linux-backends:"))
        #expect(!workflow.contains("GTK launch target interaction smoke"))
        #expect(!workflow.contains("Qt launch target interaction smoke"))
        #expect(workflow.contains("Upload Linux backend QA artifacts"))
        #expect(workflow.contains("name: linux-backend-qa"))
        #expect(!workflow.contains("swift-gtk:"))
        #expect(!workflow.contains("name: Swift GTK"))
        #expect(!workflow.contains("name: GTK interaction smoke"))
        #expect(!workflow.contains("Upload GTK QA artifacts"))
        #expect(!workflow.contains("name: linux-gtk-qa"))
        #expect(!workflow.contains("scripts/run-linux-gtk-profile-csv.sh /tmp/quillui-profile"))
        #expect(!workflow.contains("scripts/check-linux-gtk-profile-budget.sh /tmp/quillui-profile"))
        #expect(!workflow.contains("scripts/linux-backend-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux"))
        #expect(!workflow.contains("scripts/linux-backend-interaction-check.sh .qa/quill-chat-linux-toolbar-menu-gtk.png quill-chat-linux"))
        #expect(!workflow.contains("QuillSignal GTK visual smoke"))
        #expect(!workflow.contains("for product in quill-signal quill-telegram"))
        #expect(!workflow.contains("scripts/linux-gtk-visual-check.sh"))
        #expect(!workflow.contains("< <("))

        let backendCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-check.sh"),
            encoding: .utf8
        )
        let legacyGtkCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-check.sh"),
            encoding: .utf8
        )
        let limaConfig = try String(
            contentsOf: root.appendingPathComponent("scripts/lima-ubuntu-swift.yaml"),
            encoding: .utf8
        )
        #expect(backendCheck.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(backendCheck.contains("quillui_install_linux_backend_smoke_packages"))
        #expect(backendCheck.contains("scripts/linux-swift-test.sh --scratch-path .build-linux"))
        #expect(!backendCheck.contains("scripts/patch-swiftopenui-gtk-css.sh .build-linux\n\nswift test --scratch-path .build-linux"))
        #expect(backendCheck.contains("done < <(quillui_backend_app_products)"))
        #expect(backendCheck.contains("done < <(quillui_backend_app_matrix)"))
        #expect(backendCheck.contains("done < <(quillui_backend_generated_app_matrix)"))
        #expect(backendCheck.contains("done < <(quillui_backend_smoke_matrix)"))
        #expect(backendCheck.contains("BACKEND_SMOKE_ROWS=()"))
        #expect(backendCheck.contains("ALL_PRODUCTS=(\"${APP_PRODUCTS[@]}\" \"${BACKEND_SMOKE_PRODUCTS[@]}\")"))
        #expect(backendCheck.contains("BIN_PATH=\"$(QUILLUI_LINUX_BACKEND=gtk swift build --scratch-path .build-linux --show-bin-path)\""))
        #expect(backendCheck.contains("for product in \"${ALL_PRODUCTS[@]}\""))
        #expect(backendCheck.contains("build_backend=\"$(quillui_require_backend_for_product \"$product\")\""))
        #expect(backendCheck.contains("quillui_require_backend_product_build_stamp \"$ROOT_DIR/.build-linux\" \"$product\" \"$build_backend\""))
        #expect(backendCheck.contains("quillui_record_backend_product_build \"$ROOT_DIR/.build-linux\" \"$product\" \"$build_backend\""))
        #expect(backendCheck.contains("continue"))
        #expect(backendCheck.contains("QUILLUI_LINUX_BACKEND=\"$build_backend\" swift build --scratch-path .build-linux --product \"$product\""))
        #expect(!backendCheck.contains("done\nBIN_PATH=\"$(swift build --scratch-path .build-linux --show-bin-path)\""))
        #expect(backendCheck.contains("APP_SMOKE_ROWS=()"))
        #expect(backendCheck.contains("GENERATED_APP_SMOKE_ROWS=()"))
        #expect(backendCheck.contains("run_executable_smoke()"))
        #expect(backendCheck.contains("run_smoke \"$product\" \"$backend\""))
        #expect(backendCheck.contains("run_smoke \"$product\""))
        #expect(backendCheck.contains("run_executable_smoke \"$product\" \"$QUILL_CHAT_BIN_DIR/$product\" \"$backend\""))
        #expect(backendCheck.contains("backend launch fixture/backend rows"))
        #expect(backendCheck.contains("generated app/backend rows"))
        #expect(backendCheck.contains("requested_backend=\"${2:-}\""))
        #expect(backendCheck.contains("effective_backend=\"$(quillui_requested_backend_for_product \"$product\")\""))
        #expect(backendCheck.contains("quillui_append_backend_launch_environment app_environment \"$product\" \"\" \"$effective_backend\""))
        #expect(backendCheck.contains("Linux backend build completed."))
        #expect(backendCheck.contains("Headless backend smoke completed for ${#APP_SMOKE_ROWS[@]} app/backend rows"))
        #expect(!backendCheck.contains("QUILLUI_BACKEND=gtk \"$QUILL_CHAT_EXECUTABLE\""))
        #expect(!backendCheck.contains("install_packages()"))
        #expect(!backendCheck.contains("run_smoke quill-enchanted"))
        #expect(!backendCheck.contains("run_smoke quill-enchanted-upstream-slice"))
        #expect(legacyGtkCheck.contains("linux-backend-check.sh"))
        #expect(!legacyGtkCheck.contains("swift build --scratch-path .build-linux --product"))
        #expect(limaConfig.contains("scripts/linux-backend-check.sh"))
        #expect(!limaConfig.contains("scripts/linux-gtk-check.sh"))

        let profileScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-profile.sh"),
            encoding: .utf8
        )
        let legacyProfileScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-profile.sh"),
            encoding: .utf8
        )
        let visualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-visual-check.sh"),
            encoding: .utf8
        )
        let smokeMatrixRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-backend-smoke-matrix.sh"),
            encoding: .utf8
        )
        let smokeLib = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"),
            encoding: .utf8
        )
        let legacyVisualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-visual-check.sh"),
            encoding: .utf8
        )
        let csvRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh"),
            encoding: .utf8
        )
        let legacyCSVRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-gtk-profile-csv.sh"),
            encoding: .utf8
        )
        let budgetScript = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh"),
            encoding: .utf8
        )
        let legacyBudgetScript = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-gtk-profile-budget.sh"),
            encoding: .utf8
        )
        let backendProducts = try String(contentsOf: matrixScript, encoding: .utf8)
        let backendProductBuildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-linux-backend-products.sh"),
            encoding: .utf8
        )
        #expect(backendProducts.contains("quillui_backend_app_products()"))
        #expect(backendProducts.contains("quillui_backend_app_backends()"))
        #expect(backendProducts.contains("quillui_backend_fixed_app_backend_overrides()"))
        #expect(backendProducts.contains("quillui_backend_fixed_backend_for_app_product()"))
        #expect(backendProducts.contains("quillui_backend_app_backends_for_product()"))
        #expect(backendProducts.contains("quillui_backend_matrix_for_products()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_build_product_rows()"))
        #expect(backendProducts.contains("quillui_normalize_backend_identifier()"))
        #expect(backendProducts.contains("quillui_require_backend_identifier()"))
        #expect(backendProducts.contains("quillui_require_linux_build_backend_identifier()"))
        #expect(backendProducts.contains("quillui_backend_build_stamp_path()"))
        #expect(backendProducts.contains("quillui_record_backend_product_build()"))
        #expect(backendProducts.contains("quillui_require_backend_product_build_stamp()"))
        #expect(!backendProducts.contains("quillui_backend_identifier_or_raw()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_products()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_emit_matrix_for_product_rows \"$product_rows\""))
        #expect(backendProducts.contains("quillui_backend_generated_app_products()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_modes()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_matrix()"))
        #expect(backendProducts.contains("quillui_normalize_backend_smoke_interaction_mode()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_verify_product()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_verify_matrix()"))
        #expect(backendProducts.contains("open-panel"))
        #expect(backendProducts.contains("banner-sheet"))
        #expect(backendProducts.contains("quillui_backend_profile_products()"))
        #expect(backendProducts.contains("done < <(quillui_backend_smoke_products)"))
        #expect(backendProducts.contains("quillui_backend_generated_app_products\n  quillui_backend_smoke_products"))
        #expect(backendProducts.contains("quillui_backend_profile_matrix()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix\n  quillui_backend_generated_app_matrix\n  quillui_backend_smoke_matrix"))
        #expect(backendProducts.contains("quillui_backend_product_list_contains()"))
        #expect(backendProducts.contains("quillui_is_backend_smoke_product()"))
        #expect(backendProducts.contains("quillui_is_backend_generated_app_product()"))
        #expect(backendProducts.contains("quillui_alias_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_common_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_visual_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_interaction_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_profile_env()"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_LAYOUT_DEBUG QUILLUI_GTK_LAYOUT_DEBUG QUILLUI_QT_LAYOUT_DEBUG\n  quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE"))
        #expect(backendProducts.contains("backend_prefix=\"QUILLUI_QT_\""))
        #expect(backendProducts.contains("normalize-backend)"))
        #expect(backendProducts.contains("require-backend)"))
        #expect(backendProducts.contains("require-linux-build-backend)"))
        #expect(backendProducts.contains("build-product-matrix)"))
        #expect(backendProducts.contains("all-app-backends)"))
        #expect(backendProducts.contains("is-generated-app)"))
        #expect(backendProducts.contains("fixed-app-backends)"))
        #expect(backendProducts.contains("native-runtime-backends)"))
        #expect(backendProducts.contains("native-product-runtime-overrides)"))
        #expect(backendProducts.contains("platform-runtime-fallback)"))
        #expect(backendProducts.contains("has-native-runtime)"))
        #expect(backendProducts.contains("runtime-backend)"))
        #expect(backendProducts.contains("runtime-mode)"))
        #expect(backendProducts.contains("runtime-availability)"))
        #expect(backendProducts.contains("validate-runtime-availability)"))
        #expect(backendProducts.contains("validate-integrity)"))
        #expect(backendProducts.contains("runtime-backend-for-product)"))
        #expect(backendProducts.contains("runtime-availabilities)"))
        #expect(backendProducts.contains("quillui_backend_native_runtime_backends()"))
        #expect(backendProducts.contains("quillui_backend_native_product_runtime_overrides()"))
        #expect(backendProducts.contains("quillui_backend_native_runtime_backend_for_product()"))
        #expect(backendProducts.contains("quillui_platform_runtime_fallback_backend()"))
        #expect(backendProducts.contains("quillui_backend_has_native_runtime()"))
        #expect(backendProducts.contains("quillui_runtime_backend_for_backend()"))
        #expect(backendProducts.contains("quillui_runtime_backend_for_product()"))
        #expect(backendProducts.contains("quillui_backend_runtime_mode_for_pair()"))
        #expect(backendProducts.contains("quillui_backend_runtime_mode_for_backend()"))
        #expect(backendProducts.contains("quillui_backend_runtime_availability_for_backend()"))
        #expect(backendProducts.contains("quillui_backend_runtime_availability_for_product()"))
        #expect(backendProducts.contains("quillui_backend_runtime_availabilities()"))
        #expect(backendProducts.contains("quillui_backend_validate_runtime_availability_row()"))
        #expect(backendProducts.contains("quillui_backend_validate_runtime_availability()"))
        #expect(backendProducts.contains("quillui_backend_validate_runtime_availability_for_product()"))
        #expect(backendProducts.contains("quillui_backend_validate_integrity()"))
        #expect(backendProducts.contains("quillui_backend_runtime_matrix_for_rows()"))
        #expect(backendProducts.contains("quillui_backend_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_profile_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS QUILLUI_GTK_PROFILE_MAX_STARTUP_MS QUILLUI_QT_PROFILE_MAX_STARTUP_MS\n  quillui_alias_backend_common_env"))
        #expect(backendProductBuildScript.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(backendProductBuildScript.contains("all-app-backends"))
        #expect(backendProductBuildScript.contains("quillui_backend_build_product_rows \"$MATRIX_COMMAND\""))
        #expect(!backendProductBuildScript.contains("quillui_manifest_product_rows()"))
        #expect(backendProductBuildScript.contains("quillui_require_backend_for_product \"$product\""))
        #expect(backendProductBuildScript.contains("quillui_require_linux_build_backend_identifier \"$manifest_backend\""))
        #expect(backendProductBuildScript.contains("quillui_require_linux_build_backend_identifier \"$requested_backend\""))
        #expect(backendProductBuildScript.contains("QUILLUI_LINUX_BACKEND=\"$build_backend\""))
        #expect(backendProductBuildScript.contains("swift build --scratch-path \"$SCRATCH_PATH\" --product \"$product\""))
        #expect(backendProductBuildScript.contains("quillui_record_backend_product_build \"$(quillui_absolute_scratch_path)\" \"$product\" \"$build_backend\""))
        #expect(backendProductBuildScript.contains("patch-swiftopenui-gtk-css.sh"))
        #expect(profileScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(profileScript.contains("quillui_install_linux_backend_smoke_packages"))
        #expect(profileScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" exe"))
        #expect(profileScript.contains("REQUESTED_BACKEND=\"${4:-${QUILLUI_BACKEND:-}}\""))
        #expect(profileScript.contains(Self.profileCSVHeader))
        #expect(profileScript.contains("REQUESTED_BACKEND_LABEL=\"$(quillui_requested_backend_for_product \"$PRODUCT\")\""))
        #expect(profileScript.contains("runtime_availability=\"$(quillui_backend_runtime_availability_for_product \"$PRODUCT\" \"$REQUESTED_BACKEND_LABEL\")\""))
        #expect(profileScript.contains("IFS=$'\\t' read -r REQUESTED_BACKEND_LABEL RUNTIME_BACKEND_LABEL runtime_mode <<<\"$runtime_availability\""))
        #expect(profileScript.contains("emit_profile_row()"))
        #expect(profileScript.contains("quillui_export_backend_argument \"$REQUESTED_BACKEND\" \"$PRODUCT\""))
        #expect(profileScript.contains("quillui_alias_backend_build_env"))
        #expect(!profileScript.contains("patch-swiftopenui-gtk-css.sh"))
        #expect(!profileScript.contains("swift build --scratch-path \"$ROOT_DIR/.build-linux\" --product \"$PRODUCT\""))
        #expect(csvRunner.contains("MATRIX_COMMAND=\"\""))
        #expect(csvRunner.contains("--matrix profile-matrix|profile-runtime-matrix"))
        #expect(csvRunner.contains("Unsupported backend profile matrix command"))
        #expect(csvRunner.contains("RUNTIME_MATRIX_COMMAND=\"$MATRIX_COMMAND\""))
        #expect(csvRunner.contains("RUNTIME_MATRIX_COMMAND=\"profile-runtime-matrix\""))
        #expect(csvRunner.contains("\"$ROOT_DIR/scripts/quillui-backend-products.sh\" \"$RUNTIME_MATRIX_COMMAND\""))
        #expect(csvRunner.contains("quillui_profile_build_cache_key()"))
        #expect(csvRunner.contains("build_cache_key=\"$(quillui_profile_build_cache_key \"$product\" \"$requested_backend\" \"$runtime_backend\")\""))
        #expect(csvRunner.contains("printf '%s:%s\\n' \"$product\" \"$runtime_backend\""))
        #expect(csvRunner.contains("quillui_is_backend_generated_app_product \"$product\""))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$requested_backend\")"))
        #expect(legacyProfileScript.contains("linux-backend-profile.sh"))
        #expect(visualScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(visualScript.contains("REQUESTED_BACKEND=\"${3:-${QUILLUI_BACKEND:-}}\""))
        #expect(visualScript.contains("quillui_export_backend_argument \"$REQUESTED_BACKEND\" \"$PRODUCT\""))
        #expect(visualScript.contains("quillui_alias_backend_build_env"))
        #expect(smokeMatrixRunner.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeMatrixRunner.contains("app-matrix|interaction-matrix|interaction-extra-mode-matrix|generated-app-matrix|smoke-matrix|smoke-interaction-matrix"))
        #expect(smokeMatrixRunner.contains("quillui_smoke_runtime_matrix_command()"))
        #expect(smokeMatrixRunner.contains("RUNTIME_MATRIX_COMMAND=\"$(quillui_smoke_runtime_matrix_command \"$MATRIX_COMMAND\")\""))
        #expect(smokeMatrixRunner.contains("CHECK_SCRIPT=\"$ROOT_DIR/scripts/linux-backend-visual-check.sh\""))
        #expect(smokeMatrixRunner.contains("CHECK_SCRIPT=\"$ROOT_DIR/scripts/linux-backend-interaction-check.sh\""))
        #expect(smokeMatrixRunner.contains("OUTPUT_TEMPLATE must include {product} and {backend}; mode matrices must also"))
        #expect(smokeMatrixRunner.contains("OUTPUT_TEMPLATE must include {mode} for $MATRIX_COMMAND"))
        #expect(smokeMatrixRunner.contains("Backend mode runtime matrix row has an empty mode"))
        #expect(smokeMatrixRunner.contains("Backend runtime matrix row has an unexpected mode column"))
        #expect(smokeMatrixRunner.contains("quillui_backend_validate_runtime_availability_for_product \"$product\" \"$backend\" \"$runtime_backend\" \"$runtime_mode\""))
        #expect(smokeMatrixRunner.contains("Backend runtime matrix row has invalid runtime availability"))
        #expect(smokeMatrixRunner.contains("quillui_is_backend_generated_app_product \"$product\""))
        #expect(smokeMatrixRunner.contains("build_cache_key=\"$(quillui_smoke_build_cache_key \"$product\" \"$requested_backend\" \"$runtime_backend\")\""))
        #expect(smokeMatrixRunner.contains("printf '%s:%s\\n' \"$product\" \"$runtime_backend\""))
        #expect(smokeMatrixRunner.contains("smoke_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$requested_backend\")"))
        #expect(smokeMatrixRunner.contains("smoke_environment+=(\"QUILLUI_BACKEND_INTERACTION_MODE=$mode\")"))
        #expect(smokeMatrixRunner.contains("QUILLUI_BACKEND_SKIP_BUILD=1"))
        #expect(smokeMatrixRunner.contains("env \"${smoke_environment[@]}\" \"$CHECK_SCRIPT\" \"$output_path\" \"$product\" \"$requested_backend\""))
        #expect(smokeMatrixRunner.contains("\"$ROOT_DIR/scripts/quillui-backend-products.sh\" \"$RUNTIME_MATRIX_COMMAND\""))
        #expect(smokeLib.contains("source \"$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeLib.contains("quillui_export_backend_argument()"))
        #expect(smokeLib.contains("requested_backend=\"$(quillui_require_requested_backend_for_product \"$product\")\""))
        #expect(smokeLib.contains("requested_backend=\"$(quillui_validate_requested_backend_for_product \"$product\" \"$requested_backend\")\""))
        #expect(smokeLib.contains("quillui_alias_backend_build_env()"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD"))
        #expect(smokeLib.contains("qt6-base-dev"))
        #expect(smokeLib.contains("linux_build_backend=\"$(quillui_require_backend_for_product \"$product\")\""))
        #expect(smokeLib.contains("QUILLUI_LINUX_BACKEND=\"$linux_build_backend\""))
        #expect(smokeLib.contains("quillui_assign_output()"))
        #expect(smokeLib.contains("printf -v \"$output_var\" \"%s\" \"$value\""))
        #expect(smokeLib.contains("quillui_start_xvfb()"))
        #expect(smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_BACKEND_APP_EXECUTABLE\""))
        #expect(smokeLib.contains("${QUILLUI_BACKEND_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_require_backend_product_build_stamp"))
        #expect(smokeLib.contains("quillui_record_backend_product_build"))
        #expect(!smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_GTK_APP_EXECUTABLE\""))
        #expect(!smokeLib.contains("${QUILLUI_GTK_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_install_linux_backend_smoke_packages()"))
        #expect(smokeLib.contains("quillui_normalize_x_display_id()"))
        #expect(smokeLib.contains("quillui_stop_process_if_running()"))
        #expect(smokeLib.contains("quillui_is_quill_chat_mac_reference_product()"))
        #expect(smokeLib.contains("quillui_backend_screen_size()"))
        #expect(smokeLib.contains("quillui_backend_reference_window_defaults()"))
        #expect(smokeLib.contains("quillui_find_visible_window_by_name()"))
        #expect(smokeLib.contains("quillui_find_visible_window_for_pid()"))
        #expect(smokeLib.contains("quillui_find_any_visible_window()"))
        #expect(smokeLib.contains("quillui_find_quill_chat_reference_window()"))
        #expect(smokeLib.contains("quillui_place_reference_window()"))
        #expect(smokeLib.contains("quillui_backend_visual_verify_product()"))
        #expect(smokeLib.contains("quillui_backend_interaction_verify_product()"))
        #expect(smokeLib.contains("quill-wireguard-qt-tunnel-selection"))
        #expect(smokeLib.contains("quill-wireguard-qt-name-edit"))
        #expect(smokeLib.contains("quill-wireguard-qt-import-paste"))
        #expect(smokeLib.contains("quill-wireguard-qt-import-file"))
        #expect(smokeLib.contains("quillui_backend_smoke_interaction_verify_product \"$product\" \"$interaction_mode\""))
        #expect(smokeLib.contains("quillui_append_backend_launch_environment()"))
        #expect(smokeLib.contains("quillui_append_backend_runtime_environment()"))
        #expect(smokeLib.contains("quillui_append_environment_assignment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_fixture_data_environment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment_if_needed()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_profile_fixture_environment_if_needed()"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(smokeLib.contains("QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(smokeLib.contains("QUILLUI_QT_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(smokeLib.contains("QUILLUI_QT_DEFAULT_WINDOW_HEIGHT=$reference_window_height"))
        #expect(smokeLib.contains("QUILLUI_QT_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_REFERENCE_MODE=1"))
        #expect(smokeLib.contains("quillui_resolve_linux_backend_executable()"))
        #expect(smokeLib.contains("quillui_seed_quill_chat_reference_data()"))
        #expect(legacyVisualScript.contains("scripts/linux-backend-visual-check.sh"))
        #expect(!legacyVisualScript.contains("quillui_alias_env"))
        #expect(profileScript.contains("quillui_alias_backend_profile_env"))
        #expect(profileScript.contains("quillui_append_backend_runtime_environment"))
        #expect(profileScript.contains("quillui_append_quill_chat_profile_fixture_environment_if_needed"))
        #expect(profileScript.contains("\"$PRODUCT\""))
        #expect(profileScript.contains("\"$display_id\""))
        #expect(profileScript.contains("\"$REQUESTED_BACKEND\""))
        #expect(profileScript.contains("quillui_normalize_x_display_id \"${QUILLUI_BACKEND_PROFILE_DISPLAY:-95}\""))
        #expect(profileScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!profileScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(profileScript.contains("quillui_backend_screen_size \"$PRODUCT\" \"${QUILLUI_BACKEND_PROFILE_SCREEN_SIZE:-}\""))
        #expect(profileScript.contains("quillui_find_any_visible_window \"$display_id\""))
        #expect(profileScript.contains("quillui_start_xvfb \"$display_id\" \"$screen_size\" /tmp/quillui-profile-xvfb.log xvfb_pid"))
        #expect(profileScript.contains("quillui_stop_process_if_running \"${app_pid:-}\""))
        #expect(profileScript.contains("quillui_stop_process_if_running \"${xvfb_pid:-}\""))
        #expect(profileScript.contains("emit_profile_row -1 -1 -1 -1 xvfb-failed"))
        #expect(!profileScript.contains("screen_size=\"${QUILLUI_BACKEND_PROFILE_SCREEN_SIZE:-1180x760x24}\""))
        #expect(!profileScript.contains("Xvfb \"$display_id\" -screen 0 \"$screen_size\""))
        #expect(!profileScript.contains("${QUILLUI_GTK_PROFILE_DISPLAY:-"))
        #expect(visualScript.contains("quillui_alias_backend_visual_env"))
        #expect(visualScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!visualScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(visualScript.contains("\"${QUILLUI_BACKEND_VISUAL_SCREEN_SIZE:-${QUILLUI_BACKEND_SCREEN_SIZE:-}}\""))
        #expect(visualScript.contains("quillui_is_quill_chat_mac_reference_product \"$PRODUCT\""))
        #expect(visualScript.contains("quillui_find_quill_chat_reference_window \"$DISPLAY_ID\""))
        #expect(visualScript.contains("quillui_place_reference_window \"$DISPLAY_ID\" \"$window_id\""))
        #expect(!visualScript.contains("is_quill_chat_mac_reference()"))
        #expect(visualScript.contains("DISPLAY_ID=\"$(quillui_normalize_x_display_id \"${QUILLUI_BACKEND_VISUAL_DISPLAY:-:94}\")\""))
        #expect(visualScript.contains("quillui_start_xvfb \"$DISPLAY_ID\" \"$SCREEN_SIZE\" /tmp/quillui-xvfb.log xvfb_pid"))
        #expect(visualScript.contains("quillui_stop_process_if_running \"${app_pid:-}\""))
        #expect(visualScript.contains("quillui_stop_process_if_running \"$xvfb_pid\""))
        #expect(visualScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" APP_EXECUTABLE"))
        #expect(visualScript.contains("quillui_append_backend_runtime_environment"))
        #expect(visualScript.contains("\"$PRODUCT\""))
        #expect(visualScript.contains("\"$DISPLAY_ID\""))
        #expect(visualScript.contains("\"$REQUESTED_BACKEND\""))
        #expect(visualScript.contains("quillui_backend_visual_verify_product \"$PRODUCT\" VERIFY_PRODUCT"))
        #expect(!visualScript.contains("${QUILLUI_GTK_VISUAL_DISPLAY:-"))
        #expect(!visualScript.contains("${QUILLUI_GTK_VERIFY_PRODUCT:-"))
        #expect(visualScript.contains("verify-backend-screenshot.py"))
        #expect(!visualScript.contains("verify-gtk-screenshot.py"))
        #expect(!visualScript.contains("install_packages()"))
        #expect(!visualScript.contains("build_and_resolve_executable()"))
        #expect(csvRunner.contains("QUILLUI_BACKEND_PROFILE_COMMAND"))
        #expect(csvRunner.contains("quillui_alias_backend_profile_env"))
        #expect(csvRunner.contains("$ROOT_DIR/scripts/linux-backend-profile.sh"))
        #expect(csvRunner.contains("QUILLUI_BACKEND_PROFILE_SETTLE"))
        #expect(csvRunner.contains(Self.profileCSVHeader))
        #expect(!csvRunner.contains("${QUILLUI_GTK_PROFILE_COMMAND:-"))
        #expect(!csvRunner.contains("${QUILLUI_GTK_PROFILE_SETTLE:-"))
        #expect(csvRunner.contains("PRODUCT<TAB>BACKEND"))
        #expect(csvRunner.contains("BUILT_PROFILE_PRODUCTS_LIST=$'\\n'"))
        #expect(csvRunner.contains("quillui_profile_product_was_built()"))
        #expect(csvRunner.contains("quillui_profile_build_cache_key()"))
        #expect(csvRunner.contains("build_cache_key=\"$(quillui_profile_build_cache_key \"$product\" \"$requested_backend\" \"$runtime_backend\")\""))
        #expect(csvRunner.contains("printf '%s:%s\\n' \"$product\" \"$runtime_backend\""))
        #expect(csvRunner.contains("quillui_is_backend_generated_app_product \"$product\""))
        #expect(csvRunner.contains("quillui_require_backend_identifier \"$backend\""))
        #expect(csvRunner.contains("requested_backend=\"$(quillui_requested_backend_for_product \"$product\")\""))
        #expect(csvRunner.contains("quillui_backend_validate_runtime_availability_for_product \"$product\" \"$requested_backend\" \"$provided_runtime_backend\" \"$provided_runtime_mode\""))
        #expect(csvRunner.contains("runtime_availability=\"$(quillui_backend_runtime_availability_for_product \"$product\" \"$requested_backend\")\""))
        #expect(csvRunner.contains("IFS=$'\\t' read -r requested_backend runtime_backend runtime_mode <<<\"$runtime_availability\""))
        #expect(csvRunner.contains("profile-row-unsupported-backend"))
        #expect(csvRunner.contains("profile-row-runtime-backend-mismatch"))
        #expect(csvRunner.contains("profile-row-runtime-mode-mismatch"))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_BACKEND_SKIP_BUILD=1\")"))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_BACKEND=$backend\")"))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$requested_backend\")"))
        #expect(csvRunner.contains("profiler_arguments+=(\"$backend\")"))
        #expect(csvRunner.contains("profile_command=(env)"))
        #expect(csvRunner.contains("profile_command+=(\"${profiler_environment[@]}\")"))
        #expect(csvRunner.contains("\"${profile_command[@]}\" \"$PROFILE_SCRIPT\" \"${profiler_arguments[@]}\""))
        #expect(csvRunner.contains("-v requested_backend=\"$requested_backend\""))
        #expect(csvRunner.contains("-v runtime_backend=\"$runtime_backend\""))
        #expect(csvRunner.contains("-v runtime_mode=\"$runtime_mode\""))
        #expect(legacyCSVRunner.contains("run-linux-backend-profile-csv.sh"))
        #expect(budgetScript.contains("QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT"))
        #expect(budgetScript.contains("quillui_alias_backend_profile_env"))
        #expect(budgetScript.contains("REQUIRE_BACKEND_MATRIX=0"))
        #expect(budgetScript.contains("--require-backend-matrix)"))
        #expect(budgetScript.contains(Self.profileCSVHeader))
        #expect(budgetScript.contains("requested_backend = $2"))
        #expect(budgetScript.contains("runtime_backend = $3"))
        #expect(budgetScript.contains("runtime_mode = $4"))
        #expect(budgetScript.contains("build_ms = $5"))
        #expect(budgetScript.contains("is_runtime_mode(value)"))
        #expect(budgetScript.contains("validation_output=\"$(quillui_backend_validate_runtime_availability_for_product \"$product\" \"$requested_backend\" \"$runtime_backend\" \"$runtime_mode\" 2>&1)\""))
        #expect(budgetScript.contains("profile budget failed: $product $validation_line"))
        #expect(budgetScript.contains("done < <(quillui_backend_profile_matrix)"))
        #expect(budgetScript.contains("quillui_require_backend_identifier \"$expected_backend\""))
        #expect(budgetScript.contains("missing required backend profile row"))
        #expect(!budgetScript.contains("${QUILLUI_GTK_PROFILE_MAX_CPU_PCT:-"))
        #expect(legacyBudgetScript.contains("check-linux-backend-profile-budget.sh"))
    }

    @Test("backend smoke matrix runner expands rows and skips repeated product builds")
    func backendSmokeMatrixRunnerExpandsRowsAndSkipsRepeatedProductBuilds() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-smoke-matrix.sh")

        let generated = try runScript(
            script,
            arguments: [
                "--dry-run",
                "--skip-repeated-products",
                "visual",
                "generated-app-matrix",
                ".qa/{product}-generated-{backend}.png"
            ]
        )
        #expect(generated.status == 0, Comment(rawValue: generated.output))
        #expect(generated.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "visual\tquill-chat-linux\tgtk\tgtk\tnative\t.qa/quill-chat-linux-generated-gtk.png\t0",
            "visual\tquill-chat-linux\tqt\tgtk\tplatformFallback\t.qa/quill-chat-linux-generated-qt.png\t0"
        ])

        let smoke = try runScript(
            script,
            arguments: [
                "--dry-run",
                "interaction",
                "smoke-matrix",
                ".qa/{product}-open-{backend}.png"
            ]
        )
        #expect(smoke.status == 0, Comment(rawValue: smoke.output))
        #expect(smoke.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-open-gtk.png\t0",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-open-qt.png\t0"
        ])

        let smokeInteractions = try runScript(
            script,
            arguments: [
                "--dry-run",
                "--skip-repeated-products",
                "interaction",
                "smoke-interaction-matrix",
                ".qa/{product}-{mode}-{backend}.png"
            ]
        )
        #expect(smokeInteractions.status == 0, Comment(rawValue: smokeInteractions.output))
        #expect(smokeInteractions.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-open-panel-gtk.png\t0\topen-panel",
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-sidebar-button-gtk.png\t1\tsidebar-button",
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-banner-button-gtk.png\t1\tbanner-button",
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-nested-sheet-gtk.png\t1\tnested-sheet",
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-sidebar-sheet-gtk.png\t1\tsidebar-sheet",
            "interaction\tquill-gtk-interaction-smoke\tgtk\tgtk\tnative\t.qa/quill-gtk-interaction-smoke-banner-sheet-gtk.png\t1\tbanner-sheet",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-open-panel-qt.png\t0\topen-panel",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-sidebar-button-qt.png\t1\tsidebar-button",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-banner-button-qt.png\t1\tbanner-button",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-nested-sheet-qt.png\t1\tnested-sheet",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-sidebar-sheet-qt.png\t1\tsidebar-sheet",
            "interaction\tquill-qt-interaction-smoke\tqt\tgtk\tplatformFallback\t.qa/quill-qt-interaction-smoke-banner-sheet-qt.png\t1\tbanner-sheet"
        ])

        let appExtraInteractions = try runScript(
            script,
            arguments: [
                "--dry-run",
                "interaction",
                "interaction-extra-mode-matrix",
                ".qa/{product}-{mode}-{backend}.png"
            ]
        )
        #expect(appExtraInteractions.status == 0, Comment(rawValue: appExtraInteractions.output))
        #expect(appExtraInteractions.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "interaction\tquill-wireguard-qt\tqt\tqt\tnative\t.qa/quill-wireguard-qt-import-paste-qt.png\t0\timport-paste",
            "interaction\tquill-wireguard-qt\tqt\tqt\tnative\t.qa/quill-wireguard-qt-import-file-qt.png\t0\timport-file"
        ])

        let malformedTemplate = try runScript(
            script,
            arguments: ["--dry-run", "visual", "app-matrix", ".qa/{product}.png"]
        )
        #expect(malformedTemplate.status != 0)
        #expect(malformedTemplate.output.contains("OUTPUT_TEMPLATE must include {product} and {backend}"))

        let modeTemplateWithoutMode = try runScript(
            script,
            arguments: ["--dry-run", "interaction", "smoke-interaction-matrix", ".qa/{product}-{backend}.png"]
        )
        #expect(modeTemplateWithoutMode.status != 0)
        #expect(modeTemplateWithoutMode.output.contains("OUTPUT_TEMPLATE must include {mode} for smoke-interaction-matrix"))

        let modeMatrixWithVisualKind = try runScript(
            script,
            arguments: ["--dry-run", "visual", "smoke-interaction-matrix", ".qa/{product}-{mode}-{backend}.png"]
        )
        #expect(modeMatrixWithVisualKind.status != 0)
        #expect(modeMatrixWithVisualKind.output.contains("smoke-interaction-matrix is only supported for interaction smokes"))

        let appModeTemplateWithoutMode = try runScript(
            script,
            arguments: ["--dry-run", "interaction", "interaction-extra-mode-matrix", ".qa/{product}-{backend}.png"]
        )
        #expect(appModeTemplateWithoutMode.status != 0)
        #expect(appModeTemplateWithoutMode.output.contains("OUTPUT_TEMPLATE must include {mode} for interaction-extra-mode-matrix"))
    }

    @Test("backend product helper maps GTK and Qt defaults")
    func backendProductHelperMapsDefaults() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        func runtimeRows(for matrixRows: [String]) -> [String] {
            matrixRows.map { row in
                let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
                let product = String(fields[0])
                let backend = String(fields[1])
                let runtimeBackend = Self.expectedRuntimeBackend(product: product, backend: backend)
                let runtimeMode = Self.expectedRuntimeMode(product: product, backend: backend)
                return "\(row)\t\(runtimeBackend)\t\(runtimeMode)"
            }
        }

        let smokeProducts = try runScript(script, arguments: ["smoke-products"])
        #expect(smokeProducts.status == 0, Comment(rawValue: smokeProducts.output))
        #expect(smokeProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedSmokeProducts)

        let expectedSmokeMatrix = ["quill-gtk-interaction-smoke\tgtk", "quill-qt-interaction-smoke\tqt"]
        let smokeMatrix = try runScript(script, arguments: ["smoke-matrix"])
        #expect(smokeMatrix.status == 0, Comment(rawValue: smokeMatrix.output))
        #expect(smokeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == expectedSmokeMatrix)

        let expectedSmokeRuntimeMatrix = runtimeRows(for: expectedSmokeMatrix)
        let smokeRuntimeMatrix = try runScript(script, arguments: ["smoke-runtime-matrix"])
        #expect(smokeRuntimeMatrix.status == 0, Comment(rawValue: smokeRuntimeMatrix.output))
        #expect(smokeRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == expectedSmokeRuntimeMatrix)

        let expectedSmokeInteractionModes = [
            "open-panel",
            "sidebar-button",
            "banner-button",
            "nested-sheet",
            "sidebar-sheet",
            "banner-sheet"
        ]
        let smokeInteractionModes = try runScript(script, arguments: ["smoke-interaction-modes"])
        #expect(smokeInteractionModes.status == 0, Comment(rawValue: smokeInteractionModes.output))
        #expect(smokeInteractionModes.output.split(whereSeparator: \.isNewline).map(String.init) == expectedSmokeInteractionModes)

        let smokeInteractionMatrix = try runScript(script, arguments: ["smoke-interaction-matrix"])
        #expect(smokeInteractionMatrix.status == 0, Comment(rawValue: smokeInteractionMatrix.output))
        #expect(
            smokeInteractionMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == expectedSmokeMatrix.flatMap { row in
                    expectedSmokeInteractionModes.map { "\(row)\t\($0)" }
                }
        )

        let smokeInteractionRuntimeMatrix = try runScript(script, arguments: ["smoke-interaction-runtime-matrix"])
        #expect(smokeInteractionRuntimeMatrix.status == 0, Comment(rawValue: smokeInteractionRuntimeMatrix.output))
        #expect(
            smokeInteractionRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == expectedSmokeRuntimeMatrix.flatMap { row in
                    expectedSmokeInteractionModes.map { "\(row)\t\($0)" }
                }
        )

        let expectedInteractionExtraModeMatrix = [
            "quill-wireguard-qt\tqt\timport-paste",
            "quill-wireguard-qt\tqt\timport-file"
        ]
        let interactionExtraModeMatrix = try runScript(script, arguments: ["interaction-extra-mode-matrix"])
        #expect(interactionExtraModeMatrix.status == 0, Comment(rawValue: interactionExtraModeMatrix.output))
        #expect(interactionExtraModeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == expectedInteractionExtraModeMatrix)

        let interactionExtraModeRuntimeMatrix = try runScript(script, arguments: ["interaction-extra-mode-runtime-matrix"])
        #expect(interactionExtraModeRuntimeMatrix.status == 0, Comment(rawValue: interactionExtraModeRuntimeMatrix.output))
        #expect(interactionExtraModeRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "quill-wireguard-qt\tqt\tqt\tnative\timport-paste",
            "quill-wireguard-qt\tqt\tqt\tnative\timport-file"
        ])

        let expectedSmokeInteractionVerifyMatrix = expectedSmokeMatrix.flatMap { row in
            let product = row.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return expectedSmokeInteractionModes.map { mode in
                let suffix: String
                switch mode {
                case "nested-sheet", "sidebar-sheet", "banner-sheet":
                    suffix = "sheet"
                case "sidebar-button":
                    suffix = "sidebar"
                case "banner-button":
                    suffix = "banner"
                default:
                    suffix = "open"
                }
                return "\(row)\t\(mode)\t\(product)-\(suffix)"
            }
        }
        let smokeInteractionVerifyMatrix = try runScript(script, arguments: ["smoke-interaction-verify-matrix"])
        #expect(smokeInteractionVerifyMatrix.status == 0, Comment(rawValue: smokeInteractionVerifyMatrix.output))
        #expect(
            smokeInteractionVerifyMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == expectedSmokeInteractionVerifyMatrix
        )

        let normalizedClickMode = try runScript(script, arguments: ["normalize-smoke-interaction-mode", "click"])
        #expect(normalizedClickMode.status == 0, Comment(rawValue: normalizedClickMode.output))
        #expect(normalizedClickMode.output.trimmingCharacters(in: .whitespacesAndNewlines) == "open-panel")

        let unknownMode = try runScript(script, arguments: ["normalize-smoke-interaction-mode", "unknown-mode"])
        #expect(unknownMode.status != 0)
        #expect(unknownMode.output.contains("Unsupported backend smoke interaction mode: unknown-mode"))

        let sidebarVerifier = try runScript(
            script,
            arguments: ["smoke-interaction-verify-product", "quill-qt-interaction-smoke", "sidebar-button"]
        )
        #expect(sidebarVerifier.status == 0, Comment(rawValue: sidebarVerifier.output))
        #expect(sidebarVerifier.output.trimmingCharacters(in: .whitespacesAndNewlines) == "quill-qt-interaction-smoke-sidebar")

        let profileProducts = try runScript(script, arguments: ["profile-products"])
        #expect(profileProducts.status == 0, Comment(rawValue: profileProducts.output))
        let actualProfileProducts = profileProducts.output.split(whereSeparator: \.isNewline).map(String.init)
        let expectedProfileProducts = Self.expectedAppProducts
            + Self.expectedGeneratedAppProducts
            + Self.expectedSmokeProducts
        #expect(actualProfileProducts == expectedProfileProducts)

        let profileMatrix = try runScript(script, arguments: ["profile-matrix"])
        #expect(profileMatrix.status == 0, Comment(rawValue: profileMatrix.output))
        let actualProfileMatrix = profileMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
        let expectedProfileMatrix = Self.expectedAppMatrix
            + Self.expectedGeneratedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
            + expectedSmokeMatrix
        #expect(actualProfileMatrix == expectedProfileMatrix)

        let profileRuntimeMatrix = try runScript(script, arguments: ["profile-runtime-matrix"])
        #expect(profileRuntimeMatrix.status == 0, Comment(rawValue: profileRuntimeMatrix.output))
        #expect(profileRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == runtimeRows(for: expectedProfileMatrix))

        let appBackends = try runScript(script, arguments: ["app-backends"])
        #expect(appBackends.status == 0, Comment(rawValue: appBackends.output))
        #expect(appBackends.output.split(whereSeparator: \.isNewline).map(String.init) == ["gtk", "qt"])

        let appMatrix = try runScript(script, arguments: ["app-matrix"])
        #expect(appMatrix.status == 0, Comment(rawValue: appMatrix.output))
        #expect(
            appMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == Self.expectedAppMatrix
        )

        let appRuntimeMatrix = try runScript(script, arguments: ["app-runtime-matrix"])
        #expect(appRuntimeMatrix.status == 0, Comment(rawValue: appRuntimeMatrix.output))
        #expect(appRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == runtimeRows(for: Self.expectedAppMatrix))

        let interactionProducts = try runScript(script, arguments: ["interaction-apps"])
        #expect(interactionProducts.status == 0, Comment(rawValue: interactionProducts.output))
        #expect(interactionProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedAppProducts)

        let interactionMatrix = try runScript(script, arguments: ["interaction-matrix"])
        #expect(interactionMatrix.status == 0, Comment(rawValue: interactionMatrix.output))
        #expect(interactionMatrix.output == appMatrix.output)

        let interactionRuntimeMatrix = try runScript(script, arguments: ["interaction-runtime-matrix"])
        #expect(interactionRuntimeMatrix.status == 0, Comment(rawValue: interactionRuntimeMatrix.output))
        #expect(interactionRuntimeMatrix.output == appRuntimeMatrix.output)

        let generatedProducts = try runScript(script, arguments: ["generated-apps"])
        #expect(generatedProducts.status == 0, Comment(rawValue: generatedProducts.output))
        #expect(generatedProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedGeneratedAppProducts)

        let generatedMatrix = try runScript(script, arguments: ["generated-app-matrix"])
        #expect(generatedMatrix.status == 0, Comment(rawValue: generatedMatrix.output))
        let expectedGeneratedMatrix = Self.expectedGeneratedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
        #expect(
            generatedMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == expectedGeneratedMatrix
        )

        let generatedRuntimeMatrix = try runScript(script, arguments: ["generated-app-runtime-matrix"])
        #expect(generatedRuntimeMatrix.status == 0, Comment(rawValue: generatedRuntimeMatrix.output))
        #expect(generatedRuntimeMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == runtimeRows(for: expectedGeneratedMatrix))

        let knownGeneratedProduct = try runScript(script, arguments: ["is-generated-app", "quill-chat-linux"])
        #expect(knownGeneratedProduct.status == 0, Comment(rawValue: knownGeneratedProduct.output))

        let appGeneratedProduct = try runScript(script, arguments: ["is-generated-app", "quill-icecubes"])
        #expect(appGeneratedProduct.status != 0)

        let knownSmokeProduct = try runScript(script, arguments: ["is-smoke-product", "quill-qt-interaction-smoke"])
        #expect(knownSmokeProduct.status == 0, Comment(rawValue: knownSmokeProduct.output))

        let appProduct = try runScript(script, arguments: ["is-smoke-product", "quill-icecubes"])
        #expect(appProduct.status != 0)

        let qtBackend = try runScript(script, arguments: ["backend-for-product", "quill-qt-interaction-smoke"])
        #expect(qtBackend.status == 0, Comment(rawValue: qtBackend.output))
        #expect(qtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let wireGuardQtBackend = try runScript(script, arguments: ["backend-for-product", "quill-wireguard-qt"])
        #expect(wireGuardQtBackend.status == 0, Comment(rawValue: wireGuardQtBackend.output))
        #expect(wireGuardQtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let gtkBackend = try runScript(script, arguments: ["backend-for-product", "quill-icecubes"])
        #expect(gtkBackend.status == 0, Comment(rawValue: gtkBackend.output))
        #expect(gtkBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let unknownProductBackend = try runScript(script, arguments: ["backend-for-product", "unknown-product"])
        #expect(unknownProductBackend.status != 0)
        #expect(unknownProductBackend.output.contains("Unsupported QuillUI backend product: unknown-product"))

        let overrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-icecubes"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(overrideBackend.status == 0, Comment(rawValue: overrideBackend.output))
        #expect(overrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let aliasOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-icecubes"],
            environment: ["QUILLUI_BACKEND": " Qt6 "]
        )
        #expect(aliasOverrideBackend.status == 0, Comment(rawValue: aliasOverrideBackend.output))
        #expect(aliasOverrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let matchingFixedQtOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-wireguard-qt"],
            environment: ["QUILLUI_BACKEND": " Qt6 "]
        )
        #expect(matchingFixedQtOverrideBackend.status == 0, Comment(rawValue: matchingFixedQtOverrideBackend.output))
        #expect(matchingFixedQtOverrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let mismatchedFixedQtOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-wireguard-qt"],
            environment: ["QUILLUI_BACKEND": "gtk"]
        )
        #expect(mismatchedFixedQtOverrideBackend.status != 0)
        #expect(mismatchedFixedQtOverrideBackend.output.contains("Product quill-wireguard-qt is fixed to the qt Linux backend; requested gtk would mix manifest and runtime backend paths."))

        let mismatchedFixedGtkOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-wireguard"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(mismatchedFixedGtkOverrideBackend.status != 0)
        #expect(mismatchedFixedGtkOverrideBackend.output.contains("Product quill-wireguard is fixed to the gtk Linux backend; requested qt would mix manifest and runtime backend paths."))

        let unknownProductOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "unknown-product"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(unknownProductOverrideBackend.status == 0, Comment(rawValue: unknownProductOverrideBackend.output))
        #expect(unknownProductOverrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let unknownProductRequestedBackend = try runScript(script, arguments: ["requested-backend", "unknown-product"])
        #expect(unknownProductRequestedBackend.status != 0)
        #expect(unknownProductRequestedBackend.output.contains("Unsupported QuillUI backend product: unknown-product"))

        let invalidOverrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-icecubes"],
            environment: ["QUILLUI_BACKEND": "unknown"]
        )
        #expect(invalidOverrideBackend.status != 0)
        #expect(invalidOverrideBackend.output.contains("Unsupported QuillUI backend: unknown"))

        let normalizedQtBackend = try runScript(script, arguments: ["normalize-backend", " Qt6 "])
        #expect(normalizedQtBackend.status == 0, Comment(rawValue: normalizedQtBackend.output))
        #expect(normalizedQtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let normalizedGtkBackend = try runScript(script, arguments: ["normalize-backend", "GTK4"])
        #expect(normalizedGtkBackend.status == 0, Comment(rawValue: normalizedGtkBackend.output))
        #expect(normalizedGtkBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let requiredQtBackend = try runScript(script, arguments: ["require-backend", " Qt6 "])
        #expect(requiredQtBackend.status == 0, Comment(rawValue: requiredQtBackend.output))
        #expect(requiredQtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let requiredQtBuildBackend = try runScript(script, arguments: ["require-linux-build-backend", " Qt6 "])
        #expect(requiredQtBuildBackend.status == 0, Comment(rawValue: requiredQtBuildBackend.output))
        #expect(requiredQtBuildBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let requiredSwiftUIBuildBackend = try runScript(script, arguments: ["require-linux-build-backend", "swift-ui"])
        #expect(requiredSwiftUIBuildBackend.status != 0)
        #expect(requiredSwiftUIBuildBackend.output.contains("Unsupported QuillUI Linux build backend: swift-ui; expected gtk or qt."))

        let nativeRuntimeBackends = try runScript(script, arguments: ["native-runtime-backends"])
        #expect(nativeRuntimeBackends.status == 0, Comment(rawValue: nativeRuntimeBackends.output))
        #expect(nativeRuntimeBackends.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let fixedAppBackends = try runScript(script, arguments: ["fixed-app-backends"])
        #expect(fixedAppBackends.status == 0, Comment(rawValue: fixedAppBackends.output))
        #expect(fixedAppBackends.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "quill-wireguard\tgtk",
            "quill-wireguard-qt\tqt"
        ])

        let allAppBuildMatrix = try runScript(script, arguments: ["build-product-matrix", "all-app-backends"])
        #expect(allAppBuildMatrix.status == 0, Comment(rawValue: allAppBuildMatrix.output))
        #expect(allAppBuildMatrix.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedAppBuildPlan)

        let backendAppsBuildMatrix = try runScript(script, arguments: ["build-product-matrix", "backend-apps"])
        #expect(backendAppsBuildMatrix.status == 0, Comment(rawValue: backendAppsBuildMatrix.output))
        #expect(backendAppsBuildMatrix.output == allAppBuildMatrix.output)

        let integrity = try runScript(script, arguments: ["validate-integrity"])
        #expect(integrity.status == 0, Comment(rawValue: integrity.output))
        #expect(integrity.output.trimmingCharacters(in: .whitespacesAndNewlines) == "backend product matrix ok")

        let buildScript = root.appendingPathComponent("scripts/build-linux-backend-products.sh")
        let fixedAppBuildPlan = try runScript(buildScript, arguments: ["--dry-run", "fixed-app-backends"])
        #expect(fixedAppBuildPlan.status == 0, Comment(rawValue: fixedAppBuildPlan.output))
        #expect(fixedAppBuildPlan.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "quill-wireguard\tgtk",
            "quill-wireguard-qt\tqt"
        ])

        let appBuildPlan = try runScript(buildScript, arguments: ["--dry-run", "app-matrix"])
        #expect(appBuildPlan.status == 0, Comment(rawValue: appBuildPlan.output))
        #expect(appBuildPlan.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedAppBuildPlan)

        let allAppBuildPlan = try runScript(buildScript, arguments: ["--dry-run", "all-app-backends"])
        #expect(allAppBuildPlan.status == 0, Comment(rawValue: allAppBuildPlan.output))
        #expect(allAppBuildPlan.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedAppBuildPlan)

        let backendAppsBuildPlan = try runScript(buildScript, arguments: ["--dry-run", "backend-apps"])
        #expect(backendAppsBuildPlan.status == 0, Comment(rawValue: backendAppsBuildPlan.output))
        #expect(backendAppsBuildPlan.output == allAppBuildPlan.output)

        let nativeProductRuntimeOverrides = try runScript(script, arguments: ["native-product-runtime-overrides"])
        #expect(nativeProductRuntimeOverrides.status == 0, Comment(rawValue: nativeProductRuntimeOverrides.output))
        #expect(nativeProductRuntimeOverrides.output.trimmingCharacters(in: .whitespacesAndNewlines) == "quill-wireguard-qt\tqt\tqt")

        let platformRuntimeFallback = try runScript(script, arguments: ["platform-runtime-fallback"])
        #expect(platformRuntimeFallback.status == 0, Comment(rawValue: platformRuntimeFallback.output))
        #expect(platformRuntimeFallback.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let gtkHasNativeRuntime = try runScript(script, arguments: ["has-native-runtime", "GTK4"])
        #expect(gtkHasNativeRuntime.status == 0, Comment(rawValue: gtkHasNativeRuntime.output))

        let qtHasNativeRuntime = try runScript(script, arguments: ["has-native-runtime", "Qt6"])
        #expect(qtHasNativeRuntime.status != 0)

        let runtimeGtkBackend = try runScript(script, arguments: ["runtime-backend", "GTK4"])
        #expect(runtimeGtkBackend.status == 0, Comment(rawValue: runtimeGtkBackend.output))
        #expect(runtimeGtkBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let runtimeQtBackend = try runScript(script, arguments: ["runtime-backend", " Qt6 "])
        #expect(runtimeQtBackend.status == 0, Comment(rawValue: runtimeQtBackend.output))
        #expect(runtimeQtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let runtimeGtkMode = try runScript(script, arguments: ["runtime-mode", "GTK4"])
        #expect(runtimeGtkMode.status == 0, Comment(rawValue: runtimeGtkMode.output))
        #expect(runtimeGtkMode.output.trimmingCharacters(in: .whitespacesAndNewlines) == "native")

        let runtimeQtMode = try runScript(script, arguments: ["runtime-mode", " Qt6 "])
        #expect(runtimeQtMode.status == 0, Comment(rawValue: runtimeQtMode.output))
        #expect(runtimeQtMode.output.trimmingCharacters(in: .whitespacesAndNewlines) == "platformFallback")

        let runtimeQtAvailability = try runScript(script, arguments: ["runtime-availability", " Qt6 "])
        #expect(runtimeQtAvailability.status == 0, Comment(rawValue: runtimeQtAvailability.output))
        #expect(runtimeQtAvailability.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt\tgtk\tplatformFallback")

        let validRuntimeAvailability = try runScript(script, arguments: ["validate-runtime-availability", " Qt6 ", "GTK4", "platformFallback"])
        #expect(validRuntimeAvailability.status == 0, Comment(rawValue: validRuntimeAvailability.output))
        #expect(validRuntimeAvailability.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt\tgtk\tplatformFallback")

        let invalidRuntimeBackend = try runScript(script, arguments: ["validate-runtime-availability", "Qt6", "Qt6", "platformFallback"])
        #expect(invalidRuntimeBackend.status != 0)
        #expect(invalidRuntimeBackend.output.contains("runtime_backend=qt does not match requested_backend=qt expected_runtime=gtk"))

        let invalidRuntimeMode = try runScript(script, arguments: ["validate-runtime-availability", "Qt6", "GTK4", "native"])
        #expect(invalidRuntimeMode.status != 0)
        #expect(invalidRuntimeMode.output.contains("runtime_mode=native does not match requested_backend=qt expected_mode=platformFallback"))

        let runtimeSwiftUIBackend = try runScript(script, arguments: ["runtime-backend", "swift-ui"])
        #expect(runtimeSwiftUIBackend.status == 0, Comment(rawValue: runtimeSwiftUIBackend.output))
        #expect(runtimeSwiftUIBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let runtimeProductBackend = try runScript(script, arguments: ["runtime-backend-for-product", "quill-qt-interaction-smoke"])
        #expect(runtimeProductBackend.status == 0, Comment(rawValue: runtimeProductBackend.output))
        #expect(runtimeProductBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let runtimeWireGuardQtProductBackend = try runScript(script, arguments: ["runtime-backend-for-product", "quill-wireguard-qt"])
        #expect(runtimeWireGuardQtProductBackend.status == 0, Comment(rawValue: runtimeWireGuardQtProductBackend.output))
        #expect(runtimeWireGuardQtProductBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let mismatchedRuntimeWireGuardQtProductBackend = try runScript(
            script,
            arguments: ["runtime-backend-for-product", "quill-wireguard-qt"],
            environment: ["QUILLUI_BACKEND": "gtk"]
        )
        #expect(mismatchedRuntimeWireGuardQtProductBackend.status != 0)
        #expect(mismatchedRuntimeWireGuardQtProductBackend.output.contains("Product quill-wireguard-qt is fixed to the qt Linux backend; requested gtk would mix manifest and runtime backend paths."))

        let runtimeAvailabilities = try runScript(script, arguments: ["runtime-availabilities"])
        #expect(runtimeAvailabilities.status == 0, Comment(rawValue: runtimeAvailabilities.output))
        #expect(runtimeAvailabilities.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "gtk\tgtk\tnative",
            "qt\tgtk\tplatformFallback"
        ])

        let unknownRuntimeProductBackend = try runScript(script, arguments: ["runtime-backend-for-product", "unknown-product"])
        #expect(unknownRuntimeProductBackend.status != 0)
        #expect(unknownRuntimeProductBackend.output.contains("Unsupported QuillUI backend product: unknown-product"))

        let normalizedSwiftUIBackend = try runScript(script, arguments: ["normalize-backend", "swift-ui"])
        #expect(normalizedSwiftUIBackend.status == 0, Comment(rawValue: normalizedSwiftUIBackend.output))
        #expect(normalizedSwiftUIBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "swiftui")

        let invalidBackend = try runScript(script, arguments: ["normalize-backend", "unknown"])
        #expect(invalidBackend.status != 0)

        let unsupportedRequiredBackend = try runScript(script, arguments: ["require-backend", "unknown"])
        #expect(unsupportedRequiredBackend.status != 0)
        #expect(unsupportedRequiredBackend.output.contains("Unsupported QuillUI backend: unknown"))
    }

    @Test("backend alias helper accepts scoped GTK and Qt controls")
    func backendAliasHelperAcceptsScopedGTKAndQtControls() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-backend-aliases-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let probe = temporaryDirectory.appendingPathComponent("alias-probe.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        source "\(root.path)/scripts/quillui-backend-products.sh"

        QUILLUI_BACKEND=Qt6
        QUILLUI_QT_PROFILE_COMMAND=/tmp/qt-profiler
        QUILLUI_GTK_PROFILE_COMMAND=/tmp/gtk-profiler
        export QUILLUI_BACKEND QUILLUI_QT_PROFILE_COMMAND QUILLUI_GTK_PROFILE_COMMAND
        quillui_alias_backend_profile_env
        printf 'profile=%s\\n' "$QUILLUI_BACKEND_PROFILE_COMMAND"
        printf 'profile-gtk=%s\\n' "$QUILLUI_GTK_PROFILE_COMMAND"
        printf 'profile-qt=%s\\n' "$QUILLUI_QT_PROFILE_COMMAND"

        unset QUILLUI_BACKEND_PROFILE_COMMAND
        unset QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_BACKEND_PROFILE_SCREEN_SIZE
        unset QUILLUI_GTK_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE
        unset QUILLUI_QT_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE
        QUILLUI_BACKEND=" qt6 "
        QUILLUI_QT_VISUAL_SCREEN_SIZE=1440x900x24
        export QUILLUI_BACKEND QUILLUI_QT_VISUAL_SCREEN_SIZE
        quillui_alias_backend_visual_env
        printf 'visual=%s\\n' "$QUILLUI_BACKEND_VISUAL_SCREEN_SIZE"
        printf 'screen=%s\\n' "$QUILLUI_BACKEND_SCREEN_SIZE"
        printf 'screen-qt=%s\\n' "$QUILLUI_QT_SCREEN_SIZE"

        unset QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE
        QUILLUI_BACKEND=GTK4
        QUILLUI_QT_INTERACTION_MODE=wrong-backend
        QUILLUI_GTK_INTERACTION_MODE=prompt-send
        export QUILLUI_BACKEND QUILLUI_QT_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE
        quillui_alias_backend_interaction_env
        printf 'interaction=%s\\n' "$QUILLUI_BACKEND_INTERACTION_MODE"
        printf 'interaction-qt=%s\\n' "$QUILLUI_QT_INTERACTION_MODE"

        unset QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE
        QUILLUI_BACKEND=qt
        QUILLUI_GTK_INTERACTION_MODE=wrong-backend
        export QUILLUI_BACKEND QUILLUI_GTK_INTERACTION_MODE
        quillui_alias_backend_interaction_env
        printf 'qt-ignores-gtk-only=%s\\n' "${QUILLUI_BACKEND_INTERACTION_MODE-unset}"
        printf 'qt-ignores-gtk-only-source=%s\\n' "$QUILLUI_GTK_INTERACTION_MODE"

        unset QUILLUI_BACKEND_IMPORT_CONFIGURATION QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION
        QUILLUI_BACKEND=gtk
        QUILLUI_QT_IMPORT_CONFIGURATION=wrong-backend
        export QUILLUI_BACKEND QUILLUI_QT_IMPORT_CONFIGURATION
        quillui_alias_backend_interaction_env
        printf 'gtk-ignores-qt-only=%s\\n' "${QUILLUI_BACKEND_IMPORT_CONFIGURATION-unset}"
        printf 'gtk-ignores-qt-only-source=%s\\n' "$QUILLUI_QT_IMPORT_CONFIGURATION"

        unset QUILLUI_BACKEND_IMPORT_CONFIGURATION QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION
        unset QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE
        QUILLUI_BACKEND=qt
        QUILLUI_GTK_IMPORT_CONFIGURATION=wrong-backend
        QUILLUI_QT_IMPORT_CONFIGURATION=qt-import
        QUILLUI_GTK_IMPORT_CONFIGURATION_FILE=/tmp/wrong.conf
        QUILLUI_QT_IMPORT_CONFIGURATION_FILE=/tmp/qt.conf
        export QUILLUI_BACKEND QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION
        export QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE
        quillui_alias_backend_interaction_env
        printf 'import-config=%s\\n' "$QUILLUI_BACKEND_IMPORT_CONFIGURATION"
        printf 'import-config-qt=%s\\n' "$QUILLUI_QT_IMPORT_CONFIGURATION"
        printf 'import-config-file=%s\\n' "$QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE"
        printf 'import-config-file-qt=%s\\n' "$QUILLUI_QT_IMPORT_CONFIGURATION_FILE"

        unset QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT QUILLUI_GTK_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT
        QUILLUI_BACKEND=Qt
        QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT=11
        QUILLUI_QT_PROFILE_MAX_CPU_PCT=99
        export QUILLUI_BACKEND QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT
        quillui_alias_backend_profile_env
        printf 'cpu-qt=%s\\n' "$QUILLUI_QT_PROFILE_MAX_CPU_PCT"

        unset QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        QUILLUI_BACKEND=Qt6
        QUILLUI_GENERATED_INCLUDE_GTK_BACKEND=0
        QUILLUI_GENERATED_INCLUDE_QT_BACKEND=1
        export QUILLUI_BACKEND QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        quillui_alias_env QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        printf 'generated-entry=%s\\n' "$QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY"
        printf 'generated-entry-gtk=%s\\n' "$QUILLUI_GENERATED_INCLUDE_GTK_BACKEND"

        unset QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_BACKEND_SKIP_BUILD
        unset QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE
        unset QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD
        QUILLUI_BACKEND=gtk
        QUILLUI_GTK_APP_EXECUTABLE=/tmp/gtk-app
        QUILLUI_QT_APP_EXECUTABLE=/tmp/qt-app
        QUILLUI_GTK_SKIP_BUILD=0
        QUILLUI_QT_SKIP_BUILD=1
        export QUILLUI_BACKEND QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD
        source "\(root.path)/scripts/quillui-linux-backend-smoke-lib.sh"
        quillui_export_backend_argument " Qt6 "
        quillui_alias_backend_build_env
        printf 'build-backend=%s\\n' "$QUILLUI_BACKEND"
        printf 'build-exe=%s\\n' "$QUILLUI_BACKEND_APP_EXECUTABLE"
        printf 'build-skip=%s\\n' "$QUILLUI_BACKEND_SKIP_BUILD"

        unset QUILLUI_BACKEND
        quillui_export_backend_argument "" quill-wireguard-qt
        printf 'product-default-qt=%s\\n' "$QUILLUI_BACKEND"

        if quillui_export_backend_argument gtk quill-wireguard-qt 2>/dev/null; then
          echo "unexpected-fixed-export-success"
          exit 1
        fi
        printf 'strict-fixed-export=failed\\n'

        fixed_runtime_env=()
        if quillui_append_backend_launch_environment fixed_runtime_env quill-wireguard-qt "" gtk 2>/dev/null; then
          echo "unexpected-fixed-launch-success"
          exit 1
        fi
        printf 'strict-fixed-launch=failed\\n'

        stamp_root="\(temporaryDirectory.path)/stamp-cache"
        if quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard-qt qt 2>/dev/null; then
          echo "unexpected-missing-stamp-success"
          exit 1
        fi
        printf 'missing-build-stamp=failed\\n'
        quillui_record_backend_product_build "$stamp_root" quill-wireguard-qt qt
        quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard-qt qt
        printf 'matching-build-stamp=ok\\n'
        if quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard-qt gtk 2>/dev/null; then
          echo "unexpected-mismatched-stamp-success"
          exit 1
        fi
        printf 'mismatched-build-stamp=failed\\n'

        runtime_env=()
        quillui_append_backend_launch_environment runtime_env quill-icecubes "" " GTK4 "
        printf 'launch-backend=%s\\n' "${runtime_env[1]}"

        if quillui_export_backend_argument "not-a-backend" 2>/dev/null; then
          echo "unexpected-export-success"
          exit 1
        fi
        printf 'strict-export=failed\\n'

        invalid_runtime_env=()
        if quillui_append_backend_launch_environment invalid_runtime_env quill-icecubes "" "not-a-backend" 2>/dev/null; then
          echo "unexpected-launch-success"
          exit 1
        fi
        printf 'strict-launch=failed\\n'

        QUILLUI_BACKEND=not-a-backend
        export QUILLUI_BACKEND
        invalid_env_runtime=()
        if quillui_append_backend_launch_environment invalid_env_runtime quill-icecubes "" "" 2>/dev/null; then
          echo "unexpected-env-success"
          exit 1
        fi
        printf 'strict-env=failed\\n'

        """.write(to: probe, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)

        let result = try runScript(probe)
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output == """
        profile=/tmp/qt-profiler
        profile-gtk=/tmp/qt-profiler
        profile-qt=/tmp/qt-profiler
        visual=1440x900x24
        screen=1440x900x24
        screen-qt=1440x900x24
        interaction=prompt-send
        interaction-qt=prompt-send
        qt-ignores-gtk-only=unset
        qt-ignores-gtk-only-source=wrong-backend
        gtk-ignores-qt-only=unset
        gtk-ignores-qt-only-source=wrong-backend
        import-config=qt-import
        import-config-qt=qt-import
        import-config-file=/tmp/qt.conf
        import-config-file-qt=/tmp/qt.conf
        cpu-qt=11
        generated-entry=1
        generated-entry-gtk=1
        build-backend=qt
        build-exe=/tmp/qt-app
        build-skip=1
        product-default-qt=qt
        strict-fixed-export=failed
        strict-fixed-launch=failed
        missing-build-stamp=failed
        matching-build-stamp=ok
        mismatched-build-stamp=failed
        launch-backend=QUILLUI_BACKEND=gtk
        strict-export=failed
        strict-launch=failed
        strict-env=failed

        """)
    }

    @Test("profile budget accepts current rows and rejects bad profile rows")
    func profileBudgetAcceptsCurrentRowsAndRejectsBadRows() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let matrixScript = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let fileManager = FileManager.default
        let csv = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-\(UUID().uuidString).csv")
        defer { try? fileManager.removeItem(at: csv) }

        try """
        \(Self.profileCSVHeader)
        quill-icecubes,gtk,gtk,native,13148,6,236156,3.0,2.8,ok
        quill-netnewswire,qt,gtk,platformFallback,13105,6,235852,5.8,5.6,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let passing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(passing.status == 0, Comment(rawValue: passing.output))
        #expect(passing.output.contains("profile budget ok: quill-icecubes requested=gtk runtime=gtk"))
        #expect(passing.output.contains("profile budget ok: quill-netnewswire requested=qt runtime=gtk"))

        try """
        \(Self.profileCSVHeader)
        quill-icecubes,gtk,gtk,native,13148,6,236156,3.0,135.2,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let failing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(failing.status != 0)
        #expect(failing.output.contains("cpu_pct_steady=135.2"))

        try """
        \(Self.profileCSVHeader)
        quill-icecubes,gtk,gtk,native,13148,nope,236156,3.0,2.8,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let malformed = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(malformed.status != 0)
        #expect(malformed.output.contains("startup_ms=nope is not a non-negative integer"))

        try """
        \(Self.profileCSVHeader)
        quill-netnewswire,qt,qt,native,13105,6,235852,5.8,5.6,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let wrongRuntime = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(wrongRuntime.status != 0)
        #expect(wrongRuntime.output.contains("runtime_backend=qt does not match requested_backend=qt expected_runtime=gtk"))

        try """
        \(Self.profileCSVHeader)
        quill-netnewswire,qt,gtk,native,13105,6,235852,5.8,5.6,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let wrongRuntimeMode = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(wrongRuntimeMode.status != 0)
        #expect(wrongRuntimeMode.output.contains("runtime_mode=native does not match requested_backend=qt expected_mode=platformFallback"))

        let profileMatrix = try runScript(matrixScript, arguments: ["profile-matrix"])
        #expect(profileMatrix.status == 0, Comment(rawValue: profileMatrix.output))
        let matrixRows = profileMatrix.output
            .split(whereSeparator: \.isNewline)
            .compactMap { row -> (product: String, backend: String)? in
                let fields = row.split(separator: "\t")
                guard fields.count == 2 else { return nil }
                return (String(fields[0]), String(fields[1]))
            }
        let matrixLabels = matrixRows.map { "\($0.product)@\($0.backend)" }
        #expect(!matrixLabels.isEmpty)

        let fullMatrixRows = matrixRows
            .map { row in
                let runtimeBackend = Self.expectedRuntimeBackend(product: row.product, backend: row.backend)
                let runtimeMode = Self.expectedRuntimeMode(product: row.product, backend: row.backend)
                return "\(row.product),\(row.backend),\(runtimeBackend),\(runtimeMode),1,2,3,0.1,0.2,ok"
            }
            .joined(separator: "\n")
        try """
        \(Self.profileCSVHeader)
        \(fullMatrixRows)

        """.write(to: csv, atomically: true, encoding: .utf8)

        let strictPassing = try runScript(script, arguments: [csv.path, "--require-backend-matrix"])
        #expect(strictPassing.status == 0, Comment(rawValue: strictPassing.output))

        let missingFirstRow = matrixRows
            .dropFirst()
            .map { row in
                let runtimeBackend = Self.expectedRuntimeBackend(product: row.product, backend: row.backend)
                let runtimeMode = Self.expectedRuntimeMode(product: row.product, backend: row.backend)
                return "\(row.product),\(row.backend),\(runtimeBackend),\(runtimeMode),1,2,3,0.1,0.2,ok"
            }
            .joined(separator: "\n")
        try """
        \(Self.profileCSVHeader)
        \(missingFirstRow)

        """.write(to: csv, atomically: true, encoding: .utf8)

        let strictMissing = try runScript(script, arguments: [csv.path, "--require-backend-matrix"])
        #expect(strictMissing.status != 0)
        #expect(strictMissing.output.contains("missing required backend profile row: \(matrixLabels[0])"))
    }

    @Test("profile CSV runner shares header and failure-tolerant product loop")
    func profileCSVRunnerSharesHeaderAndFailureTolerantProductLoop() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-runner-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("fake-profiler.sh")
        try """
        #!/usr/bin/env bash
        product="$1"
        echo "$product,1,2,3,4.0,5.0,ok"
        if [[ "$product" == "second-product" ]]; then
          exit 7
        fi

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path, "first-product", "second-product"],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        \(Self.profileCSVHeader)
        first-product,,,,1,2,3,4.0,5.0,ok
        second-product,,,,1,2,3,4.0,5.0,profiler-exit-7

        """
        #expect(result.output == expected)
        let writtenCSV = try String(contentsOf: csv, encoding: .utf8)
        #expect(writtenCSV == expected)
    }

    @Test("profile CSV runner records profilers that fail before emitting rows")
    func profileCSVRunnerRecordsSilentProfilerFailures() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let budgetScript = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-silent-failure-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("silent-profiler.sh")
        try """
        #!/usr/bin/env bash
        exit 42

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path, "silent-product"],
            environment: ["QUILLUI_GTK_PROFILE_COMMAND": fakeProfiler.path]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        \(Self.profileCSVHeader)
        silent-product,,,,0,0,0,0.0,0.0,profiler-exit-42

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)

        let budget = try runScript(budgetScript, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(budget.status != 0)
        #expect(budget.output.contains("silent-product exit_status=profiler-exit-42"))
    }

    @Test("profile CSV runner normalizes backend matrix rows and rejects unsupported backends")
    func profileCSVRunnerNormalizesBackendMatrixRowsAndRejectsUnsupportedBackends() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-backend-matrix-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("backend-profiler.sh")
        try """
        #!/usr/bin/env bash
        product="$1"
        backend="${4:-}"
        if [[ "$backend" != "${QUILLUI_BACKEND:-}" ]]; then
          exit 44
        fi
        if [[ "$backend" != "gtk" && "$backend" != "qt" ]]; then
          exit 42
        fi
        case "$product" in
          quill-icecubes)
            if [[ "$backend" == "gtk" && "${QUILLUI_BACKEND_SKIP_BUILD:-0}" != "0" ]]; then
              exit 42
            fi
            if [[ "$backend" == "qt" && "${QUILLUI_BACKEND_SKIP_BUILD:-0}" != "1" ]]; then
              exit 43
            fi
            ;;
          quill-chat-linux)
            if [[ "$backend" != "${QUILLUI_APP_BACKEND_FACADE:-}" ]]; then
              exit 45
            fi
            if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" != "0" ]]; then
              exit 46
            fi
            ;;
          *)
            exit 41
            ;;
        esac
        echo "$product,1,2,3,${QUILLUI_BACKEND_SKIP_BUILD:-0}.0,5.0,ok"

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path],
            stdin: "quill-icecubes\tGTK4\tgtk\tnative\nquill-icecubes\t qt6 \tgtk\tplatformFallback\nquill-chat-linux\tgtk\tgtk\tnative\nquill-chat-linux\tqt\tgtk\tplatformFallback\nquill-icecubes\tgtk\tqt\tnative\nquill-icecubes\tqt\tgtk\tnative\nquill-icecubes\tgtk\tqtx\tnative\nquill-icecubes\tgtk\tgtk\tbogus\nquill-icecubes\tqtx\n"
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        \(Self.profileCSVHeader)
        quill-icecubes,gtk,gtk,native,1,2,3,0.0,5.0,ok
        quill-icecubes,qt,gtk,platformFallback,1,2,3,1.0,5.0,ok
        quill-chat-linux,gtk,gtk,native,1,2,3,0.0,5.0,ok
        quill-chat-linux,qt,gtk,platformFallback,1,2,3,0.0,5.0,ok
        quill-icecubes,gtk,qt,native,0,0,0,0.0,0.0,profile-row-runtime-backend-mismatch
        quill-icecubes,qt,gtk,native,0,0,0,0.0,0.0,profile-row-runtime-mode-mismatch
        quill-icecubes,gtk,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-runtime-backend
        quill-icecubes,gtk,gtk,bogus,0,0,0,0.0,0.0,profile-row-runtime-mode-mismatch
        quill-icecubes,unsupported-backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-backend

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)
    }

    @Test("profile CSV runner expands the canonical backend matrix")
    func profileCSVRunnerExpandsCanonicalBackendMatrix() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let matrixScript = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-canonical-matrix-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("matrix-profiler.sh")
        try """
        #!/usr/bin/env bash
        product="$1"
        backend="${4:-}"
        if [[ -z "$backend" ]]; then
          exit 43
        fi
        if [[ "$backend" != "${QUILLUI_BACKEND:-}" ]]; then
          exit 44
        fi
        echo "$product,1,2,3,4.0,5.0,ok"

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let matrix = try runScript(matrixScript, arguments: ["profile-matrix"])
        #expect(matrix.status == 0, Comment(rawValue: matrix.output))
        let matrixRows = matrix.output
            .split(whereSeparator: \.isNewline)
            .map { row -> (product: String, backend: String) in
                let fields = row.split(separator: "\t")
                return (String(fields[0]), String(fields[1]))
            }
        #expect(!matrixRows.isEmpty)

        let result = try runScript(
            script,
            arguments: ["--matrix", "profile-matrix", csv.path],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        \(Self.profileCSVHeader)
        \(matrixRows.map { row in
            let runtimeBackend = Self.expectedRuntimeBackend(product: row.product, backend: row.backend)
            let runtimeMode = Self.expectedRuntimeMode(product: row.product, backend: row.backend)
            return "\(row.product),\(row.backend),\(runtimeBackend),\(runtimeMode),1,2,3,4.0,5.0,ok"
        }.joined(separator: "\n"))

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)

        let unsupportedMatrix = try runScript(
            script,
            arguments: ["--matrix", "app-matrix", csv.path],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )
        #expect(unsupportedMatrix.status != 0)
        #expect(unsupportedMatrix.output.contains("Unsupported backend profile matrix command: app-matrix"))

        let mixedArguments = try runScript(
            script,
            arguments: ["--matrix", "profile-matrix", csv.path, "quill-icecubes"],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )
        #expect(mixedArguments.status != 0)
        #expect(mixedArguments.output.contains("--matrix cannot be combined with explicit product rows"))
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        stdin: String? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if let stdin {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "LinuxBackendAppMatrixTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
