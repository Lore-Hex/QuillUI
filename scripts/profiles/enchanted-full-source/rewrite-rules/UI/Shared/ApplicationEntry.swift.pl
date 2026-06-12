s{            Task\.detached \{}{<<'SWIFT'}se;
            let environment = ProcessInfo.processInfo.environment
            if environment["QUILLUI_ENCHANTED_PROFILE_MODE"] == "1"
                || environment["QUILLUI_QUILL_CHAT_PROFILE_MODE"] == "1" {
                return
            }
            
            Task.detached {
SWIFT
