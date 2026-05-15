s/var isReachable: Bool = true/var isReachable: Bool = (ProcessInfo.processInfo.environment["QUILLUI_ENCHANTED_FORCE_UNREACHABLE"] == "1" || ProcessInfo.processInfo.environment["QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE"] == "1") ? false : true/g;
s{        startCheckingReachability\(interval: pingInterval\)}{        let environment = ProcessInfo.processInfo.environment
        if environment["QUILLUI_ENCHANTED_PROFILE_MODE"] != "1" && environment["QUILLUI_QUILL_CHAT_PROFILE_MODE"] != "1" {
            startCheckingReachability(interval: pingInterval)
        }}g;
