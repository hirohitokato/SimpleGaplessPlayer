//
//  HKLOpenGLUtilities.m
//  DisplayLinkPlayer
//
//  Created by Hirohito Kato on 2014/11/12.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#import "HKLOpenGLUtilities.h"

#define LogInfo printf
#define LogError printf

#pragma mark - Shader utilities

/* Compile a shader from the provided source(s) */
GLint glueCompileShader(GLenum target, GLsizei count, const GLchar **sources, GLuint *shader)
{
    GLint status;

    *shader = glCreateShader(target);
    glShaderSource(*shader, count, sources, NULL);
    glCompileShader(*shader);

#if defined(DEBUG)
    GLint logLength = 0;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        LogInfo("Shader compile log:\n%s", log);
        free(log);
    }
#endif

    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0)
    {
        int i;

        LogError("Failed to compile shader:\n");
        for (i = 0; i < count; i++)
            LogInfo("%s", sources[i]);
    }

    return status;
}


/* Link a program with all currently attached shaders */
GLint glueLinkProgram(GLuint program)
{
    GLint status;

    glLinkProgram(program);

#if defined(DEBUG)
    GLint logLength = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
        LogInfo("Program link log:\n%s", log);
        free(log);
    }
#endif

    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == 0)
        LogError("Failed to link program %d", program);

    return status;
}


/* Validate a program (for i.e. inconsistent samplers) */
GLint glueValidateProgram(GLuint program)
{
    GLint status;

    glValidateProgram(program);

#if defined(DEBUG)
    GLint logLength = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
        LogInfo("Program validate log:\n%s", log);
        free(log);
    }
#endif

    glGetProgramiv(program, GL_VALIDATE_STATUS, &status);
    if (status == 0)
        LogError("Failed to validate program %d", program);

    return status;
}


/* Return named uniform location after linking */
GLint glueGetUniformLocation(GLuint program, const GLchar *uniformName)
{
    GLint loc;

    loc = glGetUniformLocation(program, uniformName);

    return loc;
}


/* Convenience wrapper that compiles, links, enumerates uniforms and attribs */
GLint glueCreateProgram(const GLchar *vertSource, const GLchar *fragSource,
                        GLsizei attribNameCt, const GLchar **attribNames,
                        const GLint *attribLocations,
                        GLsizei uniformNameCt, const GLchar **uniformNames,
                        GLint *uniformLocations,
                        GLuint *program)
{
    GLuint vertShader = 0, fragShader = 0, prog = 0, status = 1, i;

    // Create shader program
    prog = glCreateProgram();

    // Create and compile vertex shader
    status *= glueCompileShader(GL_VERTEX_SHADER, 1, &vertSource, &vertShader);

    // Create and compile fragment shader
    status *= glueCompileShader(GL_FRAGMENT_SHADER, 1, &fragSource, &fragShader);

    // Attach vertex shader to program
    glAttachShader(prog, vertShader);

    // Attach fragment shader to program
    glAttachShader(prog, fragShader);

    // Bind attribute locations
    // This needs to be done prior to linking
    for (i = 0; i < attribNameCt; i++)
    {
        if(strlen(attribNames[i]))
            glBindAttribLocation(prog, attribLocations[i], attribNames[i]);
    }

    // Link program
    status *= glueLinkProgram(prog);

    // Get locations of uniforms
    if (status)
    {
        for(i = 0; i < uniformNameCt; i++)
        {
            if(strlen(uniformNames[i]))
                uniformLocations[i] = glueGetUniformLocation(prog, uniformNames[i]);
        }
        *program = prog;
    }
    
    // Release vertex and fragment shaders
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);
    
    return status;
}

#pragma mark - Drawing utilities

void GetAspectFitVertices(CGSize viewSize, CGSize frameSize,
                          GLfloat *vertices/*[8]*/,
                          GLfloat *textureVertices/*[8]*/) {
    // Preserve aspect ratio; fit layer bounds
    CGSize samplingSize;
    CGSize scaleRatio = CGSizeMake( viewSize.width / frameSize.width,
                                   viewSize.height / frameSize.height );
    if ( scaleRatio.height > scaleRatio.width ) {
        samplingSize.width = 1.0;
        samplingSize.height = ( frameSize.height * scaleRatio.width ) / viewSize.height;
    }
    else {
        samplingSize.width = ( frameSize.width * scaleRatio.height ) / viewSize.width;
        samplingSize.height = 1.0;
    }

    vertices[0] = -samplingSize.width;  // bottom left
    vertices[1] =  samplingSize.height;
    vertices[2] =  samplingSize.width;  // bottom right
    vertices[3] =  samplingSize.height;
    vertices[4] = -samplingSize.width;  // top left
    vertices[5] = -samplingSize.height;
    vertices[6] =  samplingSize.width;  // top right
    vertices[7] = -samplingSize.height;

    // Perform a vertical flip by swapping the top left and the bottom left coordinate.
    // CVPixelBuffers have a top left origin and OpenGL has a bottom left origin.
    textureVertices[0] = 0.0; // top left
    textureVertices[1] = 0.0;
    textureVertices[2] = 1.0; // top right
    textureVertices[3] = 0.0;
    textureVertices[4] = 0.0; // bottom left
    textureVertices[5] = 1.0;
    textureVertices[6] = 1.0; // bottom right
    textureVertices[7] = 1.0;
}

void GetAspectFillVertices(CGSize viewSize, CGSize frameSize,
                           GLfloat *vertices/*[8]*/,
                           GLfloat *textureVertices/*[8]*/) {
    // Preserve aspect ratio; fill layer bounds
    CGSize samplingSize;
    CGSize scaleRatio = CGSizeMake( viewSize.width / frameSize.width,
                                   viewSize.height / frameSize.height );
    if ( scaleRatio.height > scaleRatio.width ) {
        samplingSize.width = viewSize.width / ( frameSize.width * scaleRatio.height );
        samplingSize.height = 1.0;
    }
    else {
        samplingSize.width = 1.0;
        samplingSize.height = viewSize.height / ( frameSize.height * scaleRatio.width );
    }

    vertices[0] = -1.0;  // bottom left
    vertices[1] = -1.0;
    vertices[2] =  1.0;  // bottom right
    vertices[3] = -1.0;
    vertices[4] = -1.0;  // top left
    vertices[5] =  1.0;
    vertices[6] =  1.0;  // top right
    vertices[7] =  1.0;

    // Perform a vertical flip by swapping the top left and the bottom left coordinate.
    // CVPixelBuffers have a top left origin and OpenGL has a bottom left origin.
    textureVertices[0] = ( 1.0 - samplingSize.width )  / 2.0; // top left
    textureVertices[1] = ( 1.0 + samplingSize.height ) / 2.0;
    textureVertices[2] = ( 1.0 + samplingSize.width )  / 2.0; // top right
    textureVertices[3] = ( 1.0 + samplingSize.height ) / 2.0;
    textureVertices[4] = ( 1.0 - samplingSize.width )  / 2.0; // bottom left
    textureVertices[5] = ( 1.0 - samplingSize.height ) / 2.0;
    textureVertices[6] = ( 1.0 + samplingSize.width )  / 2.0; // bottom right
    textureVertices[7] = ( 1.0 - samplingSize.height ) / 2.0;
}
