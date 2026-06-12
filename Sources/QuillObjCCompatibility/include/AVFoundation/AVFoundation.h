#ifndef QUILL_OBJC_AVFOUNDATION_H
#define QUILL_OBJC_AVFOUNDATION_H

#include <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreMedia/CoreMedia.h>

typedef uint32_t CMSampleBufferFlags;

static const CMSampleBufferFlags kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment = 1U << 0;

static inline size_t CMSampleBufferGetNumSamples(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return 0;
}

static inline OSStatus CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
    CMSampleBufferRef sbuf,
    const void *bufferListSizeNeededOut,
    AudioBufferList *bufferListOut,
    size_t bufferListSize,
    const void *blockBufferAllocator,
    const void *blockBufferMemoryAllocator,
    CMSampleBufferFlags flags,
    CMBlockBufferRef *blockBufferOut
) {
    (void)sbuf; (void)bufferListSizeNeededOut; (void)bufferListSize; (void)blockBufferAllocator; (void)blockBufferMemoryAllocator; (void)flags;
    if (bufferListOut != NULL) {
        bufferListOut->mNumberBuffers = 0;
    }
    if (blockBufferOut != NULL) {
        *blockBufferOut = NULL;
    }
    return noErr;
}

#if defined(__OBJC__)
typedef NS_ENUM(NSInteger, AVCaptureVideoOrientation) {
    AVCaptureVideoOrientationPortrait = 1,
    AVCaptureVideoOrientationPortraitUpsideDown = 2,
    AVCaptureVideoOrientationLandscapeRight = 3,
    AVCaptureVideoOrientationLandscapeLeft = 4,
};

@class AVURLAsset;
@class AVMutableMetadataItem;
@class AVAssetWriter;
@class AVAssetWriterInput;
@class AVAssetWriterInputPixelBufferAdaptor;

@interface AVURLAsset : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *availableMetadataFormats;
- (NSArray<AVMutableMetadataItem *> *)metadataForFormat:(NSString *)format;
@end

@interface AVMutableMetadataItem : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) id value;
@end

@interface AVAssetWriter : NSObject
@property (nonatomic) BOOL shouldOptimizeForNetworkUse;
@property (nonatomic, readonly) NSError *error;
- (instancetype)initWithURL:(NSURL *)outputURL fileType:(NSString *)outputFileType error:(NSError **)outError;
- (BOOL)canAddInput:(AVAssetWriterInput *)input;
- (BOOL)canApplyOutputSettings:(NSDictionary *)outputSettings forMediaType:(NSString *)mediaType;
- (void)addInput:(AVAssetWriterInput *)input;
- (BOOL)startWriting;
- (void)startSessionAtSourceTime:(CMTime)startTime;
- (void)finishWritingWithCompletionHandler:(void (^)(void))handler;
@end

@interface AVAssetWriterInput : NSObject
@property (nonatomic) BOOL expectsMediaDataInRealTime;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
+ (instancetype)assetWriterInputWithMediaType:(NSString *)mediaType outputSettings:(NSDictionary *)outputSettings;
- (instancetype)initWithMediaType:(NSString *)mediaType outputSettings:(NSDictionary *)outputSettings sourceFormatHint:(CMFormatDescriptionRef)sourceFormatHint;
- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)markAsFinished;
@end

@interface AVAssetWriterInputPixelBufferAdaptor : NSObject
@property (nonatomic, readonly) CVPixelBufferPoolRef pixelBufferPool;
@property (nonatomic, readonly) NSDictionary *sourcePixelBufferAttributes;
+ (instancetype)assetWriterInputPixelBufferAdaptorWithAssetWriterInput:(AVAssetWriterInput *)input sourcePixelBufferAttributes:(NSDictionary *)sourcePixelBufferAttributes;
- (BOOL)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer withPresentationTime:(CMTime)presentationTime;
@end

static NSString * const AVMetadataIdentifierID3MetadataLeadPerformer = @"AVMetadataIdentifierID3MetadataLeadPerformer";
static NSString * const AVMetadataIdentifierID3MetadataTitleDescription = @"AVMetadataIdentifierID3MetadataTitleDescription";
static NSString * const AVMetadataiTunesMetadataKeyArtist = @"AVMetadataiTunesMetadataKeyArtist";
static NSString * const AVMetadataiTunesMetadataKeySongName = @"AVMetadataiTunesMetadataKeySongName";
static NSString * const AVMetadataQuickTimeUserDataKeyArtist = @"AVMetadataQuickTimeUserDataKeyArtist";
static NSString * const AVMetadataQuickTimeUserDataKeyTrackName = @"AVMetadataQuickTimeUserDataKeyTrackName";
static NSString * const AVMetadataCommonIdentifierArtist = @"AVMetadataCommonIdentifierArtist";
static NSString * const AVMetadataCommonIdentifierTitle = @"AVMetadataCommonIdentifierTitle";
static NSString * const AVFileTypeMPEG4 = @"public.mpeg-4";
static NSString * const AVMediaTypeVideo = @"vide";
static NSString * const AVMediaTypeAudio = @"soun";
static NSString * const AVFormatIDKey = @"AVFormatIDKey";
static NSString * const AVSampleRateKey = @"AVSampleRateKey";
static NSString * const AVEncoderBitRateKey = @"AVEncoderBitRateKey";
static NSString * const AVNumberOfChannelsKey = @"AVNumberOfChannelsKey";
static NSString * const AVChannelLayoutKey = @"AVChannelLayoutKey";
static NSString * const AVVideoCodecKey = @"AVVideoCodecKey";
static NSString * const AVVideoCodecH264 = @"avc1";
static NSString * const AVVideoCodecTypeH264 = @"avc1";
static NSString * const AVVideoWidthKey = @"AVVideoWidthKey";
static NSString * const AVVideoHeightKey = @"AVVideoHeightKey";
static NSString * const AVVideoCompressionPropertiesKey = @"AVVideoCompressionPropertiesKey";
static NSString * const AVVideoAverageBitRateKey = @"AverageBitRate";
static NSString * const AVVideoProfileLevelKey = @"ProfileLevel";
static NSString * const AVVideoProfileLevelH264High40 = @"H264_High_4_0";
static NSString * const AVVideoCleanApertureKey = @"CleanAperture";
static NSString * const AVVideoCleanApertureWidthKey = @"CleanApertureWidth";
static NSString * const AVVideoCleanApertureHeightKey = @"CleanApertureHeight";
static NSString * const AVVideoCleanApertureHorizontalOffsetKey = @"CleanApertureHorizontalOffset";
static NSString * const AVVideoCleanApertureVerticalOffsetKey = @"CleanApertureVerticalOffset";
static NSString * const AVVideoPixelAspectRatioKey = @"PixelAspectRatio";
static NSString * const AVVideoPixelAspectRatioHorizontalSpacingKey = @"HorizontalSpacing";
static NSString * const AVVideoPixelAspectRatioVerticalSpacingKey = @"VerticalSpacing";
#endif

#endif
