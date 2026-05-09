s/\.padding\(\)\n(\s*)\.frame\(width: 800\)/.padding(.horizontal, 40)\n$1.padding(.vertical, 16)\n$1.frame(maxWidth: .infinity)/g;
s/\.frame\(width: 800\)/.frame(maxWidth: .infinity)/g;
