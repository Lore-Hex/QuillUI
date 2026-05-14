s/var isReachable: Bool = true/var isReachable: Bool = ProcessInfo.processInfo.environment["QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE"] == "1" ? false : true/g;
s{        startCheckingReachability\(interval: pingInterval\)}{        if ProcessInfo.processInfo.environment["QUILLUI_QUILL_CHAT_PROFILE_MODE"] != "1" {
            startCheckingReachability(interval: pingInterval)
        }}g;
