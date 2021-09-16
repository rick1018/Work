import UIKit
import CoreVideo

private let kPassThruVertex =
"\n" +
    "attribute vec4 position;\n" +
    "attribute mediump vec4 texturecoordinate;\n" +
    "varying mediump vec2 coordinate;\n" +
    "\n" +
    "void main()\n" +
    "{\n" +
    "\tgl_Position = position;\n" +
    "\tcoordinate = texturecoordinate.xy;\n" +
    "}\n" +
"\n"

private let kPassThruFragment =
"\n" +
    "varying highp vec2 coordinate;\n" +
    "uniform sampler2D videoframe;\n" +
    "\n" +
    "void main()\n" +
    "{\n" +
    "\tgl_FragColor = texture2D(videoframe, coordinate);\n" +
    "}\n" +
"\n"

private let ATTRIB_VERTEX: GLuint = 0
private let ATTRIB_TEXTUREPOSITON: GLuint = 1

@objc(OpenGLPixelBufferView)
class glDisplayview: UIView {
    private var _oglContext: EAGLContext!
    private var _textureCache: CVOpenGLESTextureCache?
    private var _width: GLint = 0
    private var _height: GLint = 0
    private var _frameBufferHandle: GLuint = 0
    private var _colorBufferHandle: GLuint = 0
    private var _program: GLuint = 0
    private var _frame: GLint = 0
    
    override class var layerClass : AnyClass {
        return CAEAGLLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Use 2x scale factor on Retina displays.
        self.contentScaleFactor = UIScreen.main.scale
        
        // Initialize OpenGL ES 2
        let eaglLayer = self.layer as! CAEAGLLayer
        eaglLayer.isOpaque = true
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        ]
        _oglContext = EAGLContext(api: .openGLES2)
        if _oglContext == nil {
            fatalError("Problem with OpenGL context.")
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initializeBuffers() -> Bool {
        var success = true
        
        glDisable(GL_DEPTH_TEST.ui)
        
        glGenFramebuffers(1, &_frameBufferHandle)
        glBindFramebuffer(GL_FRAMEBUFFER.ui, _frameBufferHandle)
        
        glGenRenderbuffers(1, &_colorBufferHandle)
        glBindRenderbuffer(GL_RENDERBUFFER.ui, _colorBufferHandle)
        
        _oglContext.renderbufferStorage(GL_RENDERBUFFER.l, from: self.layer as! CAEAGLLayer)
        
        glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_WIDTH.ui, &_width)
        glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_HEIGHT.ui, &_height)
        
        glFramebufferRenderbuffer(GL_FRAMEBUFFER.ui, GL_COLOR_ATTACHMENT0.ui, GL_RENDERBUFFER.ui, _colorBufferHandle)
        bail: repeat {
            if(glCheckFramebufferStatus(GL_FRAMEBUFFER.ui) != GL_FRAMEBUFFER_COMPLETE.ui) {
                NSLog("Failure with framebuffer generation")
                success = false
                break bail
            }
            
            //  Create a new CVOpenGLESTexture cache
            let err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, _oglContext, nil, &_textureCache)
            if err != 0 {
                NSLog("Error at CVOpenGLESTextureCacheCreate %d", err)
                success = false
                break bail
            }
            
            // attributes
            let attribLocation: [GLuint] = [
                ATTRIB_VERTEX, ATTRIB_TEXTUREPOSITON,
            ]
            let attribName: [String] = [
                "position", "texturecoordinate",
            ]
            
            glue.createProgram(kPassThruVertex, kPassThruFragment,
                attribName, attribLocation,
                [], nil,
                &_program)
            
            if _program == 0 {
                NSLog("Error creating the program")
                success = false
                break bail
            }
            _frame = glue.getUniformLocation(_program, "videoframe")
        } while false
        if !success {
            self.reset()
        }
        return success
    }
    
    func reset() {
        let oldContext = EAGLContext.current()
        if oldContext !== _oglContext {
            if !EAGLContext.setCurrent(_oglContext) {
                fatalError("Problem with OpenGL context")
            }
        }
        if _frameBufferHandle != 0 {
            glDeleteFramebuffers(1, &_frameBufferHandle)
            _frameBufferHandle = 0
        }
        if _colorBufferHandle != 0 {
            glDeleteRenderbuffers(1, &_colorBufferHandle)
            _colorBufferHandle = 0
        }
        if _program != 0 {
            glDeleteProgram(_program)
            _program = 0
        }
        if _textureCache != nil {
            _textureCache = nil
        }
        if oldContext !== _oglContext {
            EAGLContext.setCurrent(oldContext)
        }
    }
    
    deinit {
        self.reset()
    }
    
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        let squareVertices: [GLfloat] = [
            -1.0, -1.0, // bottom left
            1.0, -1.0, // bottom right
            -1.0,  1.0, // top left
            1.0,  1.0, // top right
        ]
        
        let oldContext = EAGLContext.current()
        if oldContext !== _oglContext {
            if !EAGLContext.setCurrent(_oglContext) {
                fatalError("Problem with OpenGL context")
            }
        }
        
        if _frameBufferHandle == 0 {
            let success = self.initializeBuffers()
            if !success {
                NSLog("Problem initializing OpenGL buffers.")
            }
        }
        
        // Create a CVOpenGLESTexture from a CVPixelBufferRef
        let frameWidth: size_t = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight: size_t = CVPixelBufferGetHeight(pixelBuffer)
        var texture: CVOpenGLESTexture?
        let err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
            _textureCache!,
            pixelBuffer,
            nil,
            GL_TEXTURE_2D.ui,
            GL_RGBA,
            GLsizei(frameWidth),
            GLsizei(frameHeight),
            GL_BGRA.ui,
            GL_UNSIGNED_BYTE.ui,
            0,
            &texture)
        
        
        if texture == nil || err != 0 {
            NSLog("CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err)
            return
        }
        
        // Set the view port to the entire view
        glBindFramebuffer(GL_FRAMEBUFFER.ui, _frameBufferHandle)
        glViewport(0, 0, _width, _height)
        
        glUseProgram(_program)
        glActiveTexture(GL_TEXTURE0.ui)
        glBindTexture(CVOpenGLESTextureGetTarget(texture!), CVOpenGLESTextureGetName(texture!))
        glUniform1i(_frame, 0)
        
        // Set texture parameters
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MAG_FILTER.ui, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_WRAP_S.ui, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_WRAP_T.ui, GL_CLAMP_TO_EDGE)
        
        glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT.ui, 0, 0, squareVertices)
        glEnableVertexAttribArray(ATTRIB_VERTEX)
        
        // Preserve aspect ratio; fill layer bounds
        var textureSamplingSize = CGSize()
        let cropScaleAmount = CGSize(width: self.bounds.size.width / CGFloat(frameWidth), height: self.bounds.size.height / CGFloat(frameHeight))
        if cropScaleAmount.height > cropScaleAmount.width {
            textureSamplingSize.width = self.bounds.size.width / (frameWidth.g * cropScaleAmount.height)
            textureSamplingSize.height = 1.0
        } else {
            textureSamplingSize.width = 1.0
            textureSamplingSize.height = self.bounds.size.height / (frameHeight.g * cropScaleAmount.width)
        }
        
        // Perform a vertical flip by swapping the top left and the bottom left coordinate.
        // CVPixelBuffers have a top left origin and OpenGL has a bottom left origin.
        let passThroughTextureVertices: [GLfloat] = [
            (1.0 - textureSamplingSize.width).f/2.0, (1.0 + textureSamplingSize.height).f/2.0, // top left
            (1.0 + textureSamplingSize.width).f/2.0, (1.0 + textureSamplingSize.height).f/2.0, // top right
            (1.0 - textureSamplingSize.width).f/2.0, (1.0 - textureSamplingSize.height).f/2.0, // bottom left
            (1.0 + textureSamplingSize.width).f/2.0, (1.0 - textureSamplingSize.height).f/2.0, // bottom right
        ]
        
        glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT.ui, 0, 0, passThroughTextureVertices)
        glEnableVertexAttribArray(ATTRIB_TEXTUREPOSITON)
        
        glDrawArrays(GL_TRIANGLE_STRIP.ui, 0, 4)
        
        glBindRenderbuffer(GL_RENDERBUFFER.ui, _colorBufferHandle)
        _oglContext.presentRenderbuffer(GL_RENDERBUFFER.l)
        
        glBindTexture(CVOpenGLESTextureGetTarget(texture!), 0)
        glBindTexture(GL_TEXTURE_2D.ui, 0)
        
        if oldContext !== _oglContext {
            EAGLContext.setCurrent(oldContext)
        }
    }
    
    func flushPixelBufferCache() {
        if _textureCache != nil {
            CVOpenGLESTextureCacheFlush(_textureCache!, 0)
        }
    }
    
}
