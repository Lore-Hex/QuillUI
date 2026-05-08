s/\nstruct MeetingView_Previews: PreviewProvider[\s\S]*\z/\n/s;
s/await speechRecognizer\.userInit\(\)/speechRecognizer.userInit()/g;
