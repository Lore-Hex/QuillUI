s/\.frame\(maxWidth:\.infinity, minHeight: 40\)/.frame(maxWidth:.infinity, minHeight: 56)/g;
s/\n([ \t]{12}\})\n([ \t]*)\n([ \t]{8}\})/\n$1\n            .frame(maxWidth: .infinity, alignment: .leading)\n$2\n$3/;
s/\.padding\(\.horizontal\)\n([ \t]*)\.overlay\(/.padding(.horizontal)\n$1.padding(.vertical, 8)\n$1.frame(maxWidth: .infinity)\n$1.overlay(/g;
s/RoundedRectangle\(cornerRadius: 20\)/RoundedRectangle(cornerRadius: 28)/g;
