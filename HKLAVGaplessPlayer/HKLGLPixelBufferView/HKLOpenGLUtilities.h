//
//  HKLOpenGLUtilities.h
//
//  Created by Hirohito Kato on 2014/11/12.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

#ifndef Library_HKLOpenGLUtilities_h
#define Library_HKLOpenGLUtilities_h

#import <CoreGraphics/CoreGraphics.h>
#import <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

// #define DEBUG // debug flag for shader utilities

#pragma mark - Shader utilities

GLint glueCompileShader(GLenum target, GLsizei count, const GLchar **sources, GLuint *shader);
GLint glueLinkProgram(GLuint program);
GLint glueValidateProgram(GLuint program);
GLint glueGetUniformLocation(GLuint program, const GLchar *name);

GLint glueCreateProgram(const GLchar *vertSource, const GLchar *fragSource,
                        GLsizei attribNameCt, const GLchar **attribNames,
                        const GLint *attribLocations,
                        GLsizei uniformNameCt, const GLchar **uniformNames,
                        GLint *uniformLocations,
                        GLuint *program);

#pragma mark - Drawing utilities
/**
 * アスペクト比を維持したまま、フレーム全体がフィットする頂点を計算する。
 *
 * @param viewSize[in]  表示先ビューのサイズ（pt）
 * @param frameSize[in] 表示したいフレームのサイズ（pt）
 * @param vertices[out] 計算した頂点(正規座標)を格納する配列。8要素ぶん存在すること
 * @param textureVertices[out] 計算したテクスチャの頂点(正規座標)を格納する配列。8要素ぶん存在すること
 */
void GetAspectFitVertices(CGSize viewSize, CGSize frameSize,
                          GLfloat *vertices/*[8]*/,
                          GLfloat *textureVertices/*[8]*/);

/**
 * アスペクト比を維持したまま、ビュー全体にテクスチャが描画されるための頂点を計算する。
 *
 * @param viewSize[in]  表示先ビューのサイズ（pt）
 * @param frameSize[in] 表示したいテクスチャのサイズ（pt）
 * @param vertices[out] 計算したポリゴンの頂点(正規座標)を格納する配列。8要素ぶん存在すること
 * @param textureVertices[out] 計算したテクスチャの頂点(正規座標)を格納する配列。8要素ぶん存在すること
 */
void GetAspectFillVertices(CGSize viewSize, CGSize frameSize,
                           GLfloat *vertices/*[8]*/,
                           GLfloat *textureVertices/*[8]*/);

#endif