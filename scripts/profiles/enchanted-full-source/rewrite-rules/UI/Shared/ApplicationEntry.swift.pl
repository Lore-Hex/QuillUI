s{            Task\.detached \{}{<<'SWIFT'}se;
            let environment = ProcessInfo.processInfo.environment
            if environment["QUILLUI_ENCHANTED_PROFILE_MODE"] == "1"
                || environment["QUILLUI_QUILL_CHAT_PROFILE_MODE"] == "1" {
                return
            }
            
            Task.detached {
SWIFT

# Stop the .task re-fire storm: SwiftOpenUI re-runs `.task` on every rebuild, and the
# loads (loadModels/loadConversations) update @Published stores -> schedule another
# rebuild -> .task re-runs -> loop (~12x/sec). Each rebuild destroys+recreates widgets
# (incl. the composer GtkEntry), so keystrokes race the churn and never reach $message.
# Guard the initial load to run exactly once so the rebuild storm settles and typing works.
s!import SwiftData!import SwiftData\n\nnonisolated(unsafe) private var __quillEnchantedDidInitialLoad = false!g;
s!\.task \{!.task {\n            if __quillEnchantedDidInitialLoad { return }\n            __quillEnchantedDidInitialLoad = true!g;
