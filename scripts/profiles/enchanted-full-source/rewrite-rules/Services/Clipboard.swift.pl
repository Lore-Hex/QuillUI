s/return NSImage\(data: imgData\)/return PlatformImage(data: imgData)/g;
s/\n#endif\n[ \t]*return nil\n([ \t]*\})/\n#endif\n$1/s;
