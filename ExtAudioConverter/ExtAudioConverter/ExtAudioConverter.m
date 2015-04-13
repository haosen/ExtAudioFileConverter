//
//  ExtAudioConverter.m
//  ExtAudioConverter
//
//  Created by 李 行 on 15/4/9.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ExtAudioConverter.h"

typedef struct ExtAudioConverterSettings{
    AudioStreamBasicDescription inputPCMFormat;
    AudioStreamBasicDescription outputFormat;
    
    ExtAudioFileRef             inputFile;
    AudioFileID                 outputFile;
    
    AudioStreamPacketDescription* inputPacketDescriptions;
    SInt64 outputFileStartingPacketCount;
}ExtAudioConverterSettings;

static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

void startConvert(ExtAudioConverterSettings* settings){
    //Determine the proper buffer size and calculate number of packets per buffer
    //for CBR and VBR format
    UInt32 sizePerBuffer = 32*1024;//32KB is a good start
    UInt32 sizePerPacket = settings->outputFormat.mBytesPerPacket;
    UInt32 packetsPerBuffer;
    
    //For a format that uses variable packet size
    UInt32 size = sizeof(sizePerPacket);
    if (sizePerPacket==0) {
        CheckError(ExtAudioFileGetProperty(settings->inputFile,
                                           kExtAudioFileProperty_FileMaxPacketSize,
                                           &size,
                                           &sizePerPacket),
                   "ExtAudioFileGetProperty kExtAudioFileProperty_FileMaxPacketSize failed");
        if (sizePerBuffer<sizePerPacket) {
            sizePerBuffer = sizePerPacket;
        }
        
        packetsPerBuffer = sizePerBuffer/sizePerPacket;
        settings->inputPacketDescriptions = (AudioStreamPacketDescription*)malloc(packetsPerBuffer*sizeof(AudioStreamPacketDescription));
    }else{//For a format that uses Constant packet size
        packetsPerBuffer = sizePerBuffer/sizePerPacket;
    }
    
    AudioConverterRef audioConverter;
    AudioConverterNew(&settings->inputPCMFormat,
                      &settings->outputFormat,
                      &audioConverter);
    
    while (1) {
        AudioBufferList outputBufferList;
        outputBufferList.mNumberBuffers = 1;
        outputBufferList.mBuffers[0].mNumberChannels = settings->outputFormat.mChannelsPerFrame;
        outputBufferList.mBuffers[0].mDataByteSize = sizePerBuffer;
        
        CheckError(ExtAudioFileRead(settings->inputFile,
                                    &sizePerBuffer,
                                    &outputBufferList),
                   "AudioConverterFillComplexBuffer failed");
        
        //Write the converted data to the output file
        CheckError(AudioFileWritePackets(settings->outputFile,
                                         NO,
                                         sizePerBuffer,
                                         settings->inputPacketDescriptions?settings->inputPacketDescriptions:nil,
                                         settings->outputFileStartingPacketCount,
                                         &packetsPerBuffer,
                                         outputBufferList.mBuffers[0].mData),
                   "AudioFileWritePackets failed");
        settings->outputFileStartingPacketCount += packetsPerBuffer;
    }
}

@implementation ExtAudioConverter

@synthesize sourceFile;
@synthesize outputFile;
@synthesize outputSampleRate;
@synthesize outputNumberChannels;
@synthesize outputBitDepth;

-(BOOL)convert{
    ExtAudioConverterSettings settings = {0};
    
    //Check if source file or output file is null
    if (self.sourceFile==NULL) {
        NSLog(@"Source file is not set");
        return NO;
    }
    
    if (self.outputFile==NULL) {
        NSLog(@"Output file is no set");
        return NO;
    }
    
    //Create ExtAudioFileRef
    NSURL* sourceURL = [NSURL fileURLWithPath:self.sourceFile];
    CheckError(ExtAudioFileOpenURL((__bridge CFURLRef)sourceURL,
                                   &settings.inputFile),
               "ExtAudioFileOpenURL failed");
    
    //Get input file's format
    
    
    //Set output format
    if (self.outputSampleRate==0) {
        self.outputSampleRate = 44100;
    }
    
    if (self.outputNumberChannels==0) {
        self.outputNumberChannels = 2;
    }
    
    if (self.outputBitDepth==0) {
        self.outputBitDepth = 16;
    }
    
    if (self.outputFormatID==0) {
        self.outputFormatID = kAudioFormatLinearPCM;
    }
    
    if (self.outputFileType==0) {
        self.outputFileType = kAudioFileWAVEType;
    }
    
    settings.outputFormat.mSampleRate       = self.outputSampleRate;
    settings.outputFormat.mBitsPerChannel   = self.outputSampleRate;
    settings.outputFormat.mChannelsPerFrame = self.outputNumberChannels;
    settings.outputFormat.mFormatID         = self.outputFormatID;
    
    //Create output file
    NSURL* outputURL = [NSURL fileURLWithPath:self.outputFile];
    CheckError(AudioFileCreateWithURL((__bridge CFURLRef)outputURL,
                                      self.outputFileType,
                                      &settings.outputFormat,
                                      kAudioFileFlags_EraseFile,
                                      &settings.outputFile),
               "Create output file failed");
    
    //Set input file's client data format
    //Must be PCM, thus as we say, "when you convert data, I want to receive PCM format"
    settings.inputPCMFormat.mSampleRate = 44100;
    settings.inputPCMFormat.mFormatID = kAudioFormatLinearPCM;
    settings.inputPCMFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    settings.inputPCMFormat.mFramesPerPacket = 1;
    settings.inputPCMFormat.mChannelsPerFrame = 2;
    settings.inputPCMFormat.mBytesPerFrame = 2;
    settings.inputPCMFormat.mBytesPerPacket = 2;
    settings.inputPCMFormat.mBitsPerChannel = 16;
    
    CheckError(ExtAudioFileSetProperty(settings.inputFile,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       sizeof(settings.inputPCMFormat),
                                       &settings.inputPCMFormat),
               "Setting client data format of input file failed");
    
    printf("Starting convert...");
    startConvert(&settings);
    
    return YES;
}

@end
