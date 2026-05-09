s/\.frame\(maxWidth:\.infinity, minHeight: 40\)/.frame(maxWidth:.infinity, minHeight: 56)/g;
s/\.padding\(\.horizontal\)\n([ \t]*)\.overlay\(/.padding(.horizontal)\n$1.padding(.vertical, 8)\n$1.overlay(/g;
s/RoundedRectangle\(cornerRadius: 20\)/RoundedRectangle(cornerRadius: 28)/g;
