
/*
 File: HKLGLPixelBufferView based on OpenGLPixelBufferView.h
 Abstract: The OpenGL ES view
 Version: 2.1

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2014 Apple Inc. All Rights Reserved.

 */

@import OpenGLES.EAGL;
@import QuartzCore.CAEAGLLayer;

#import <HKLAVGaplessPlayer/HKLAVGaplessPlayer-Swift.h>

#import "HKLGLPixelBufferView.h"
#import "HKLOpenGLUtilities.h"

#if !defined(_STRINGIFY)
#define __STRINGIFY( _x )   # _x
#define _STRINGIFY( _x )   __STRINGIFY( _x )
#endif

/// Vertex Shader
static const char * kPassThruVertex = _STRINGIFY(

attribute vec4 position;
attribute mediump vec4 texturecoordinate;
varying mediump vec2 coordinate;

void main()
{
    gl_Position = position;
    coordinate = texturecoordinate.xy;
}

);

/// Fragment Shader for BGRA video frame
static const char * kBGRAFragment = _STRINGIFY(

varying highp vec2 coordinate;
uniform sampler2D videoframe;

void main()
{
    gl_FragColor = texture2D(videoframe, coordinate);
}

);

/// Fragment Shader for 420v video frame
static const char * k420vFragment = _STRINGIFY(

uniform sampler2D yFrame;
uniform sampler2D uvFrame;
varying highp vec2 coordinate;

void main()
{
    mediump vec3 yuv;
    lowp vec3 rgb;

    yuv.x = texture2D(yFrame, coordinate).r;
    yuv.yz = texture2D(uvFrame, coordinate).rg - vec2(0.5, 0.5);

    // BT.601, which is the standard for SDTV is provided as a reference
    /*
     rgb = mat3(    1,       1,     1,
                    0, -.34413, 1.772,
                1.402, -.71414,     0) * yuv;
     */
    // Using BT.709 which is the standard for HDTV
    rgb = mat3(      1,       1,      1,
                     0, -.18732, 1.8556,
               1.57481, -.46813,      0) * yuv;

    gl_FragColor = vec4(rgb, 1);
}
);

// Uniform index for both/v420 shaders.
enum {
    UNIFORM_BGRA = 0,
    UNIFORM_Y = UNIFORM_BGRA,
    UNIFORM_UV,
    NUM_UNIFORMS
};

// Attribute index for both shader
enum {
    ATTRIB_VERTEX,
    ATTRIB_TEXTUREPOSITON,
    NUM_ATTRIBUTES
};

@interface HKLGLPixelBufferView ()
<HKLAVGaplessPlayerDelegate>
{
    EAGLContext *_oglContext;
    CVOpenGLESTextureCacheRef _textureCache;
    GLint _width;
    GLint _height;
    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;
    GLuint _program;
    GLint _uniforms[NUM_UNIFORMS];

    CGFloat _bgRed, _bgGreen, _bgBlue, _bgAlpha;

    OSType _pixelFormatType;
}
@end

@implementation HKLGLPixelBufferView

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];

    self.backgroundColor = self.backgroundColor;

    _pixelFormatType = kCVPixelFormatType_32BGRA;

    if (![self initializeContext]) {
        return nil;
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];

    self.backgroundColor = self.backgroundColor;

    _pixelFormatType = kCVPixelFormatType_32BGRA;

    if (![self initializeContext]) {
        return nil;
    }
    return self;
}

- (BOOL)initializeContext
{
    // On iOS8 and later we use the native scale of the screen as our content scale factor.
    //
    // This allows us to render to the exact pixel resolution of the screen
    // which avoids additional scaling and GPU rendering work.
    // For example the iPhone 6 Plus appears to UIKit as a 736 x 414 pt
    // screen with a 3x scale factor (2208 x 1242 virtual pixels).
    // But the native pixel dimensions are actually 1920 x 1080.
    // Since we are streaming 1080p buffers from the camera we can render
    // to the iPhone 6 Plus screen at 1:1 with no additional scaling
    // if we set everything up correctly.
    // Using the native scale of the screen also allows us to render
    // at full quality when using the display zoom feature on iPhone 6/6 Plus.

    // Only try to compile this code if we are using the 8.0 or later SDK.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ( [UIScreen instancesRespondToSelector:@selector(nativeScale)] )
    {
        self.contentScaleFactor = [UIScreen mainScreen].nativeScale;
    }
    else
#endif
    {
        self.contentScaleFactor = [UIScreen mainScreen].scale;
    }

    // Initialize OpenGL ES 2
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking : @(NO),
                                      kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8 };

    _oglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if ( ! _oglContext ) {
        NSLog( @"Problem with OpenGL context." );
        return NO;
    }

    return YES;
}

- (BOOL)initializeBuffers
{
    BOOL success = YES;
    glDisable( GL_DEPTH_TEST );

    glGenFramebuffers( 1, &_frameBufferHandle );
    glBindFramebuffer( GL_FRAMEBUFFER, _frameBufferHandle );

    glGenRenderbuffers( 1, &_colorBufferHandle );
    glBindRenderbuffer( GL_RENDERBUFFER, _colorBufferHandle );

    [_oglContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];

    glGetRenderbufferParameteriv( GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_width );
    glGetRenderbufferParameteriv( GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_height );

    glFramebufferRenderbuffer( GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle );
    if ( glCheckFramebufferStatus( GL_FRAMEBUFFER ) != GL_FRAMEBUFFER_COMPLETE ) {
        NSLog( @"Failure with framebuffer generation" );
        success = NO;
        goto bail;
    }

    //  Create a new CVOpenGLESTexture cache
    CVReturn err = CVOpenGLESTextureCacheCreate( kCFAllocatorDefault, NULL, _oglContext, NULL, &_textureCache );
    if ( err ) {
        NSLog( @"Error at CVOpenGLESTextureCacheCreate %d", err );
        success = NO;
        goto bail;
    }

bail:
    if ( ! success ) {
        [self reset];
    }
    return success;
}

- (BOOL)initializeProgram
{
    BOOL success = YES;

    switch (_pixelFormatType) {
        case kCVPixelFormatType_32BGRA:
            success = [self initializeProgramForBGRA];
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            success = [self initializeProgramFor420v];
            break;
        default:
            NSAssert(false, @"The format(%x) is not supported.", (unsigned int)_pixelFormatType);
            break;
    }

    if ( ! success ) {
        [self reset];
    }
    return success;
}

- (BOOL)initializeProgramForBGRA
{
    BOOL success = YES;

    // attributes
    GLint attribLocation[NUM_ATTRIBUTES] = {
        ATTRIB_VERTEX, ATTRIB_TEXTUREPOSITON,
    };
    GLchar *attribName[NUM_ATTRIBUTES] = {
        "position", "texturecoordinate",
    };

    glueCreateProgram( kPassThruVertex, kBGRAFragment,
                      NUM_ATTRIBUTES, (const GLchar **)&attribName[0], attribLocation,
                      0, 0, 0,
                      &_program );

    if ( ! _program ) {
        NSLog( @"Error creating the program" );
        success = NO;
        goto bail;
    }

    _uniforms[UNIFORM_BGRA] = glueGetUniformLocation( _program, "videoframe" );

bail:
    return success;
}

- (BOOL)initializeProgramFor420v
{
    BOOL success = YES;

    // attributes
    GLint attribLocation[NUM_ATTRIBUTES] = {
        ATTRIB_VERTEX, ATTRIB_TEXTUREPOSITON,
    };
    GLchar *attribName[NUM_ATTRIBUTES] = {
        "position", "texturecoordinate",
    };

    glueCreateProgram( kPassThruVertex, k420vFragment,
                      NUM_ATTRIBUTES, (const GLchar **)&attribName[0], attribLocation,
                      0, 0, 0,
                      &_program );

    if ( ! _program ) {
        NSLog( @"Error creating the program" );
        success = NO;
        goto bail;
    }

    // Get uniform locations.
    _uniforms[UNIFORM_Y] = glueGetUniformLocation( _program, "yFrame" );
    _uniforms[UNIFORM_UV] = glueGetUniformLocation( _program, "uvFrame" );

bail:
    return success;
}

- (void)reset
{
    EAGLContext *oldContext = [EAGLContext currentContext];
    if ( oldContext != _oglContext ) {
        if ( ! [EAGLContext setCurrentContext:_oglContext] ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Problem with OpenGL context"
                                         userInfo:nil];
            return;
        }
    }
    if ( _frameBufferHandle ) {
        glDeleteFramebuffers( 1, &_frameBufferHandle );
        _frameBufferHandle = 0;
    }
    if ( _colorBufferHandle ) {
        glDeleteRenderbuffers( 1, &_colorBufferHandle );
        _colorBufferHandle = 0;
    }

    [self deleteProgram];

    if ( _textureCache ) {
        CFRelease( _textureCache );
        _textureCache = 0;
    }
    if ( oldContext != _oglContext ) {
        [EAGLContext setCurrentContext:oldContext];
    }
}

- (void)deleteProgram
{
    if ( _program ) {
        glDeleteProgram( _program );
        _program = 0;
    }
}

- (void)dealloc
{
    [self reset];
    _oglContext = nil;
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if ( pixelBuffer == NULL ) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"NULL pixel buffer"
                                     userInfo:nil];
        return;
    }

    EAGLContext *oldContext = [EAGLContext currentContext];
    if ( oldContext != _oglContext ) {
        if ( ! [EAGLContext setCurrentContext:_oglContext] ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Problem with OpenGL context"
                                         userInfo:nil];
            return;
        }
    }

    if ( _frameBufferHandle == 0 ) {
        BOOL success = [self initializeBuffers];
        if ( ! success ) {
            NSLog( @"Problem initializing OpenGL buffers." );
            return;
        }
    }

    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if ( _program == 0 || _pixelFormatType != type) {
        _pixelFormatType = type;
        [self deleteProgram];
        BOOL success = [self initializeProgram];
        if ( ! success ) {
            NSLog( @"Problem initializing OpenGL shader program." );
            return;
        }
    }

    [self flushPixelBufferCache];

    // Create a CVOpenGLESTexture from a CVPixelBufferRef
    size_t frameWidth = CVPixelBufferGetWidth( pixelBuffer );
    size_t frameHeight = CVPixelBufferGetHeight( pixelBuffer );

    // Set the view port to the entire view
    glBindFramebuffer( GL_FRAMEBUFFER, _frameBufferHandle );
    glViewport( 0, 0, _width, _height );

    // clear old contents
    glClearColor(_bgRed, _bgGreen, _bgBlue, _bgAlpha);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram( _program );

    // BGRA uses 1 plane, and 420v uses 2 planes.
    CVOpenGLESTextureRef texture[2] = {0};
    CVReturn err;
    if (_pixelFormatType == kCVPixelFormatType_32BGRA) {
        // BGRA plane
        glActiveTexture( GL_TEXTURE0 );
        err = CVOpenGLESTextureCacheCreateTextureFromImage( kCFAllocatorDefault,
                                                           _textureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RGBA,
                                                           (GLsizei)frameWidth,
                                                           (GLsizei)frameHeight,
                                                           GL_BGRA,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &texture[0] );
        if ( ! texture[0] || err ) {
            NSLog( @"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err );
            return;
        }
        glBindTexture( CVOpenGLESTextureGetTarget( texture[0] ),
                       CVOpenGLESTextureGetName( texture[0] ) );

        // Set texture parameters
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
        glUniform1i( _uniforms[UNIFORM_BGRA], 0 );

    } else if (_pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
               _pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {

        // Y-plane
        glActiveTexture(GL_TEXTURE0);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _textureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RED_EXT,
                                                           (GLsizei)frameWidth,
                                                           (GLsizei)frameHeight,
                                                           GL_RED_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &texture[0]);
        if ( ! texture[0] || err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        glBindTexture( CVOpenGLESTextureGetTarget( texture[0] ),
                       CVOpenGLESTextureGetName( texture[0] ));

        // Set texture parameters
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );

        // UV-plane
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _textureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           (GLsizei)frameWidth/2,
                                                           (GLsizei)frameHeight/2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &texture[1]);
        if ( ! texture[1] || err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        glBindTexture( CVOpenGLESTextureGetTarget( texture[1] ),
                       CVOpenGLESTextureGetName( texture[1] ));

        // Set texture parameters
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );

        glUniform1i( _uniforms[UNIFORM_Y], 0 );
        glUniform1i( _uniforms[UNIFORM_UV], 1 );
    } else {
        NSAssert(false, @"The format(%x) is not supported.", (unsigned int)_pixelFormatType);
    }

    // Get video frame vertices preserved aspect ratio
    // @TODO: 縦で撮影した動画が横で表示される(gravityを設ける必要がありそうだ)
    GLfloat squareVertices[8];
    GLfloat textureVertices[8];

    // Get vertices preserved aspect ratio
    GetAspectFitVertices(self.bounds.size, (CGSize){frameWidth,frameHeight},
                         squareVertices, textureVertices);
    
    glVertexAttribPointer( ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, squareVertices );
    glEnableVertexAttribArray( ATTRIB_VERTEX );
    
    glVertexAttribPointer( ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices );
    glEnableVertexAttribArray( ATTRIB_TEXTUREPOSITON );
    
    glDrawArrays( GL_TRIANGLE_STRIP, 0, 4 );
    
    glBindRenderbuffer( GL_RENDERBUFFER, _colorBufferHandle );
    [_oglContext presentRenderbuffer:GL_RENDERBUFFER];

    for ( int i=0; i<2; ++i ) {
        if ( texture[i] ) {
            glBindTexture( CVOpenGLESTextureGetTarget( texture[i] ), 0 );
            CFRelease( texture[i] );
        }
    }
    glBindTexture( GL_TEXTURE_2D, 0 );

    if ( oldContext != _oglContext ) {
        [EAGLContext setCurrentContext:oldContext];
    }
}

- (void)flushPixelBufferCache
{
    if ( _textureCache ) {
        CVOpenGLESTextureCacheFlush(_textureCache, 0);
    }
}

#pragma mark - HKLAVGaplessPlayerDelegate
- (void)player:(HKLAVGaplessPlayer *)player didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) { return; }

    [self displayPixelBuffer:pixelBuffer];
}

#pragma mark -
- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    super.backgroundColor = backgroundColor;
    [backgroundColor getRed:&_bgRed
                      green:&_bgGreen
                       blue:&_bgBlue
                      alpha:&_bgAlpha];
}
@end
