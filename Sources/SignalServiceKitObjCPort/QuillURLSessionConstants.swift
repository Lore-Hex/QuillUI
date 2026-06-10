//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// swift-corelibs FoundationNetworking on Linux does NOT export the
// `NSURLSessionDownloadTaskResumeData` userInfo key constant that Darwin
// Foundation provides. SSK reads it at AttachmentDownloadManagerImpl to recover
// resume data from a failed download's NSError.userInfo. Faithful fill: on Apple
// this symbol's value is exactly this string, so any error userInfo keyed with
// the literal key matches.
//
import Foundation

#if os(Linux)
public let NSURLSessionDownloadTaskResumeData = "NSURLSessionDownloadTaskResumeData"
#endif
