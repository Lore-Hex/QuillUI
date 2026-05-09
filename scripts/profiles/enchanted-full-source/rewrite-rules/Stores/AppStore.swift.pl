s/var isReachable: Bool = true/var isReachable: Bool = ProcessInfo.processInfo.environment["QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE"] == "1" ? false : true/g;
