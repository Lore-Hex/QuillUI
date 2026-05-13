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
        "quill-wireguard"
    ]

    private static let expectedSmokeProducts = [
        "quill-gtk-interaction-smoke",
        "quill-qt-interaction-smoke"
    ]

    private static let expectedGeneratedAppProducts = [
        "quill-chat-linux"
    ]

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
        #expect(workflow.contains("scripts/quillui-backend-products.sh app-matrix"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh interaction-matrix"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh generated-app-matrix"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh smoke-products | while IFS= read -r product; do"))
        #expect(workflow.contains("Generated Enchanted backend visual smokes"))
        #expect(workflow.contains("Generated Enchanted toolbar interaction smokes"))
        #expect(workflow.contains("Quill app backend interaction smokes"))
        #expect(workflow.contains("backend-renders end-to-end"))
        #expect(!workflow.contains("GTK-renders end-to-end"))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" scripts/linux-backend-visual-check.sh \".qa/${product}-generated-${backend}.png\" \"$product\""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" QUILLUI_BACKEND_SKIP_BUILD=1 scripts/linux-backend-visual-check.sh \".qa/${product}-generated-${backend}.png\" \"$product\""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" QUILLUI_BACKEND_SKIP_BUILD=1 scripts/linux-backend-interaction-check.sh \".qa/${product}-toolbar-menu-${backend}.png\" \"$product\""))
        #expect(workflow.contains("scripts/linux-backend-visual-check.sh \".qa/${product}-visual.png\" \"$product\""))
        #expect(workflow.contains("built_products=\" \""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" scripts/linux-backend-visual-check.sh \".qa/${product}-${backend}.png\" \"$product\""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" QUILLUI_BACKEND_SKIP_BUILD=1 scripts/linux-backend-visual-check.sh \".qa/${product}-${backend}.png\" \"$product\""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" QUILLUI_BACKEND_SKIP_BUILD=1 scripts/linux-backend-interaction-check.sh \".qa/${product}-interaction-${backend}.png\" \"$product\""))
        #expect(workflow.contains("scripts/quillui-backend-products.sh profile-matrix | scripts/run-linux-backend-profile-csv.sh /tmp/quillui-profile.csv"))
        #expect(workflow.contains("scripts/check-linux-backend-profile-budget.sh /tmp/quillui-profile.csv"))
        #expect(workflow.contains("name: Swift Linux Backends"))
        #expect(workflow.contains("swift-linux-backends:"))
        #expect(workflow.contains("GTK launch target interaction smoke"))
        #expect(workflow.contains("Qt launch target interaction smoke"))
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
        #expect(backendCheck.contains("done < <(quillui_backend_app_products)"))
        #expect(backendCheck.contains("done < <(quillui_backend_app_matrix)"))
        #expect(backendCheck.contains("done < <(quillui_backend_generated_app_matrix)"))
        #expect(backendCheck.contains("done < <(quillui_backend_smoke_products)"))
        #expect(backendCheck.contains("ALL_PRODUCTS=(\"${APP_PRODUCTS[@]}\" \"${BACKEND_SMOKE_PRODUCTS[@]}\")"))
        #expect(backendCheck.contains("for product in \"${ALL_PRODUCTS[@]}\""))
        #expect(backendCheck.contains("swift build --scratch-path .build-linux --product \"$product\""))
        #expect(backendCheck.contains("APP_SMOKE_ROWS=()"))
        #expect(backendCheck.contains("GENERATED_APP_SMOKE_ROWS=()"))
        #expect(backendCheck.contains("run_executable_smoke()"))
        #expect(backendCheck.contains("run_smoke \"$product\" \"$backend\""))
        #expect(backendCheck.contains("run_smoke \"$product\""))
        #expect(backendCheck.contains("run_executable_smoke \"$product\" \"$QUILL_CHAT_BIN_DIR/$product\" \"$backend\""))
        #expect(backendCheck.contains("backend launch fixtures"))
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
        #expect(backendProducts.contains("quillui_backend_app_products()"))
        #expect(backendProducts.contains("quillui_backend_app_backends()"))
        #expect(backendProducts.contains("quillui_backend_matrix_for_products()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_products()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_products | quillui_backend_matrix_for_products"))
        #expect(backendProducts.contains("quillui_backend_generated_app_products()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_profile_products()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_products\n  quillui_backend_smoke_products"))
        #expect(backendProducts.contains("quillui_backend_profile_matrix()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix\n  quillui_backend_generated_app_matrix"))
        #expect(backendProducts.contains("quillui_is_backend_smoke_product()"))
        #expect(backendProducts.contains("quillui_alias_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_common_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_visual_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_interaction_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_profile_env()"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_LAYOUT_DEBUG QUILLUI_GTK_LAYOUT_DEBUG QUILLUI_QT_LAYOUT_DEBUG\n  quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT"))
        #expect(backendProducts.contains("backend_prefix=\"QUILLUI_QT_\""))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS QUILLUI_GTK_PROFILE_MAX_STARTUP_MS QUILLUI_QT_PROFILE_MAX_STARTUP_MS\n  quillui_alias_backend_common_env"))
        #expect(profileScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(profileScript.contains("quillui_install_linux_backend_smoke_packages"))
        #expect(profileScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" exe"))
        #expect(!profileScript.contains("patch-swiftopenui-gtk-css.sh"))
        #expect(!profileScript.contains("swift build --scratch-path \"$ROOT_DIR/.build-linux\" --product \"$PRODUCT\""))
        #expect(legacyProfileScript.contains("linux-backend-profile.sh"))
        #expect(visualScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(smokeLib.contains("source \"$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD"))
        #expect(smokeLib.contains("quillui_assign_output()"))
        #expect(smokeLib.contains("printf -v \"$output_var\" \"%s\" \"$value\""))
        #expect(smokeLib.contains("quillui_start_xvfb()"))
        #expect(smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_BACKEND_APP_EXECUTABLE\""))
        #expect(smokeLib.contains("${QUILLUI_BACKEND_SKIP_BUILD:-0}"))
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
        #expect(smokeLib.contains("quillui_append_backend_launch_environment()"))
        #expect(smokeLib.contains("quillui_append_backend_runtime_environment()"))
        #expect(smokeLib.contains("quillui_append_environment_assignment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment_if_needed()"))
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
        #expect(profileScript.contains("\"$PRODUCT\""))
        #expect(profileScript.contains("\"$display_id\""))
        #expect(profileScript.contains("quillui_normalize_x_display_id \"${QUILLUI_BACKEND_PROFILE_DISPLAY:-95}\""))
        #expect(profileScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!profileScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(profileScript.contains("quillui_backend_screen_size \"$PRODUCT\" \"${QUILLUI_BACKEND_PROFILE_SCREEN_SIZE:-}\""))
        #expect(profileScript.contains("quillui_find_any_visible_window \"$display_id\""))
        #expect(profileScript.contains("quillui_start_xvfb \"$display_id\" \"$screen_size\" /tmp/quillui-profile-xvfb.log xvfb_pid"))
        #expect(profileScript.contains("quillui_stop_process_if_running \"${app_pid:-}\""))
        #expect(profileScript.contains("quillui_stop_process_if_running \"${xvfb_pid:-}\""))
        #expect(profileScript.contains("echo \"$PRODUCT,$build_ms,-1,-1,-1,-1,xvfb-failed\""))
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
        #expect(!csvRunner.contains("${QUILLUI_GTK_PROFILE_COMMAND:-"))
        #expect(!csvRunner.contains("${QUILLUI_GTK_PROFILE_SETTLE:-"))
        #expect(csvRunner.contains("PRODUCT<TAB>BACKEND"))
        #expect(csvRunner.contains("BUILT_PROFILE_PRODUCTS_LIST=$'\\n'"))
        #expect(csvRunner.contains("quillui_profile_product_was_built()"))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_BACKEND_SKIP_BUILD=1\")"))
        #expect(csvRunner.contains("profiler_environment+=(\"QUILLUI_BACKEND=$backend\")"))
        #expect(csvRunner.contains("awk -v label=\"$label\""))
        #expect(legacyCSVRunner.contains("run-linux-backend-profile-csv.sh"))
        #expect(budgetScript.contains("QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT"))
        #expect(budgetScript.contains("quillui_alias_backend_profile_env"))
        #expect(!budgetScript.contains("${QUILLUI_GTK_PROFILE_MAX_CPU_PCT:-"))
        #expect(legacyBudgetScript.contains("check-linux-backend-profile-budget.sh"))
    }

    @Test("backend product helper maps GTK and Qt defaults")
    func backendProductHelperMapsDefaults() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")

        let smokeProducts = try runScript(script, arguments: ["smoke-products"])
        #expect(smokeProducts.status == 0, Comment(rawValue: smokeProducts.output))
        #expect(smokeProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedSmokeProducts)

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
        let expectedProfileMatrix = Self.expectedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
            + Self.expectedGeneratedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
            + ["quill-gtk-interaction-smoke\tgtk", "quill-qt-interaction-smoke\tqt"]
        #expect(actualProfileMatrix == expectedProfileMatrix)

        let appBackends = try runScript(script, arguments: ["app-backends"])
        #expect(appBackends.status == 0, Comment(rawValue: appBackends.output))
        #expect(appBackends.output.split(whereSeparator: \.isNewline).map(String.init) == ["gtk", "qt"])

        let appMatrix = try runScript(script, arguments: ["app-matrix"])
        #expect(appMatrix.status == 0, Comment(rawValue: appMatrix.output))
        #expect(
            appMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == Self.expectedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
        )

        let interactionProducts = try runScript(script, arguments: ["interaction-apps"])
        #expect(interactionProducts.status == 0, Comment(rawValue: interactionProducts.output))
        #expect(interactionProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedAppProducts)

        let interactionMatrix = try runScript(script, arguments: ["interaction-matrix"])
        #expect(interactionMatrix.status == 0, Comment(rawValue: interactionMatrix.output))
        #expect(interactionMatrix.output == appMatrix.output)

        let generatedProducts = try runScript(script, arguments: ["generated-apps"])
        #expect(generatedProducts.status == 0, Comment(rawValue: generatedProducts.output))
        #expect(generatedProducts.output.split(whereSeparator: \.isNewline).map(String.init) == Self.expectedGeneratedAppProducts)

        let generatedMatrix = try runScript(script, arguments: ["generated-app-matrix"])
        #expect(generatedMatrix.status == 0, Comment(rawValue: generatedMatrix.output))
        #expect(
            generatedMatrix.output.split(whereSeparator: \.isNewline).map(String.init)
                == Self.expectedGeneratedAppProducts.flatMap { ["\($0)\tgtk", "\($0)\tqt"] }
        )

        let knownSmokeProduct = try runScript(script, arguments: ["is-smoke-product", "quill-qt-interaction-smoke"])
        #expect(knownSmokeProduct.status == 0, Comment(rawValue: knownSmokeProduct.output))

        let appProduct = try runScript(script, arguments: ["is-smoke-product", "quill-icecubes"])
        #expect(appProduct.status != 0)

        let qtBackend = try runScript(script, arguments: ["backend-for-product", "quill-qt-interaction-smoke"])
        #expect(qtBackend.status == 0, Comment(rawValue: qtBackend.output))
        #expect(qtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let gtkBackend = try runScript(script, arguments: ["backend-for-product", "quill-icecubes"])
        #expect(gtkBackend.status == 0, Comment(rawValue: gtkBackend.output))
        #expect(gtkBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let overrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-icecubes"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(overrideBackend.status == 0, Comment(rawValue: overrideBackend.output))
        #expect(overrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")
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

        QUILLUI_BACKEND=qt
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
        QUILLUI_BACKEND=qt
        QUILLUI_QT_VISUAL_SCREEN_SIZE=1440x900x24
        export QUILLUI_BACKEND QUILLUI_QT_VISUAL_SCREEN_SIZE
        quillui_alias_backend_visual_env
        printf 'visual=%s\\n' "$QUILLUI_BACKEND_VISUAL_SCREEN_SIZE"
        printf 'screen=%s\\n' "$QUILLUI_BACKEND_SCREEN_SIZE"
        printf 'screen-qt=%s\\n' "$QUILLUI_QT_SCREEN_SIZE"

        unset QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE
        QUILLUI_BACKEND=gtk
        QUILLUI_QT_INTERACTION_MODE=wrong-backend
        QUILLUI_GTK_INTERACTION_MODE=prompt-send
        export QUILLUI_BACKEND QUILLUI_QT_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE
        quillui_alias_backend_interaction_env
        printf 'interaction=%s\\n' "$QUILLUI_BACKEND_INTERACTION_MODE"
        printf 'interaction-qt=%s\\n' "$QUILLUI_QT_INTERACTION_MODE"

        unset QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT QUILLUI_GTK_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT
        QUILLUI_BACKEND=qt
        QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT=11
        QUILLUI_QT_PROFILE_MAX_CPU_PCT=99
        export QUILLUI_BACKEND QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT
        quillui_alias_backend_profile_env
        printf 'cpu-qt=%s\\n' "$QUILLUI_QT_PROFILE_MAX_CPU_PCT"

        unset QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        QUILLUI_BACKEND=qt
        QUILLUI_GENERATED_INCLUDE_GTK_BACKEND=0
        QUILLUI_GENERATED_INCLUDE_QT_BACKEND=1
        export QUILLUI_BACKEND QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        quillui_alias_env QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND
        printf 'generated-entry=%s\\n' "$QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY"
        printf 'generated-entry-gtk=%s\\n' "$QUILLUI_GENERATED_INCLUDE_GTK_BACKEND"

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
        cpu-qt=11
        generated-entry=1
        generated-entry-gtk=1

        """)
    }

    @Test("profile budget accepts current rows and rejects bad profile rows")
    func profileBudgetAcceptsCurrentRowsAndRejectsBadRows() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let fileManager = FileManager.default
        let csv = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-\(UUID().uuidString).csv")
        defer { try? fileManager.removeItem(at: csv) }

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,6,236156,3.0,2.8,ok
        quill-netnewswire,13105,6,235852,5.8,5.6,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let passing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(passing.status == 0, Comment(rawValue: passing.output))
        #expect(passing.output.contains("profile budget ok: quill-icecubes"))
        #expect(passing.output.contains("profile budget ok: quill-netnewswire"))

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,6,236156,3.0,135.2,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let failing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(failing.status != 0)
        #expect(failing.output.contains("cpu_pct_steady=135.2"))

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,nope,236156,3.0,2.8,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let malformed = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(malformed.status != 0)
        #expect(malformed.output.contains("startup_ms=nope is not a non-negative integer"))
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
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        first-product,1,2,3,4.0,5.0,ok
        second-product,1,2,3,4.0,5.0,ok

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
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        silent-product,0,0,0,0.0,0.0,profiler-exit-42

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)

        let budget = try runScript(budgetScript, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(budget.status != 0)
        #expect(budget.output.contains("silent-product exit_status=profiler-exit-42"))
    }

    @Test("profile CSV runner accepts backend matrix rows and reuses repeated product builds")
    func profileCSVRunnerAcceptsBackendMatrixRowsAndReusesRepeatedProductBuilds() throws {
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
        if [[ "$product" != "quill-icecubes" ]]; then
          exit 41
        fi
        if [[ "${QUILLUI_BACKEND:-}" == "gtk" && "${QUILLUI_BACKEND_SKIP_BUILD:-0}" != "0" ]]; then
          exit 42
        fi
        if [[ "${QUILLUI_BACKEND:-}" == "qt" && "${QUILLUI_BACKEND_SKIP_BUILD:-0}" != "1" ]]; then
          exit 43
        fi
        if [[ "${QUILLUI_BACKEND:-}" != "gtk" && "${QUILLUI_BACKEND:-}" != "qt" ]]; then
          exit 42
        fi
        echo "$product,1,2,3,${QUILLUI_BACKEND_SKIP_BUILD:-0}.0,5.0,ok"

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path],
            stdin: "quill-icecubes\tgtk\nquill-icecubes\tqt\n"
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes@gtk,1,2,3,0.0,5.0,ok
        quill-icecubes@qt,1,2,3,1.0,5.0,ok

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)
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
