import QuillEnchantedCore

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillEnchantedApp.self)
#else
QuillEnchantedApp.main()
#endif
