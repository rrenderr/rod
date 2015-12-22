import nimx.context
import nimx.types
import nimx.image
import nimx.render_to_image
import nimx.portable_gl
import nimx.animation
import nimx.window

import tables
import rod_types
import node
import component.camera

import ray
export Viewport

proc `camera=`*(v: Viewport, c: Camera) =
    v.mCamera = c

template rootNode*(v: Viewport): Node2D = v.mRootNode

proc `rootNode=`*(v: Viewport, n: Node2D) =
    if not v.mRootNode.isNil:
        v.mRootNode.nodeWillBeRemovedFromViewport()
    v.mRootNode = n
    n.nodeWasAddedToViewport(v)

proc camera*(v: Viewport): Camera =
    if v.mCamera.isNil:
        let nodeWithCamera = v.rootNode.findNode(proc (n: Node2D): bool = not n.componentIfAvailable(Camera).isNil)
        if not nodeWithCamera.isNil:
            v.mCamera = nodeWithCamera.componentIfAvailable(Camera)
    result = v.mCamera

template bounds*(v: Viewport): Rect = v.view.bounds

template viewMatrix(v: Viewport): Matrix4 = v.mCamera.node.worldTransform.inversed

proc prepareFramebuffer(v: Viewport, i: var SelfContainedImage) =
    let vp = currentContext().gl.getViewport()
    let size = newSize(vp[2].Coord, vp[3].Coord)
    if i.isNil:
        echo "Creating buffer"
        i = imageWithSize(size)
    elif i.size != size:
        echo "Recreating buffer"
        i = imageWithSize(size)

proc prepareFramebuffers(v: Viewport) =
    v.numberOfNodesWithBackCompositionInCurrentFrame = v.numberOfNodesWithBackComposition
    if v.numberOfNodesWithBackComposition > 0:
        v.prepareFramebuffer(v.mActiveFrameBuffer)
        v.prepareFramebuffer(v.mBackupFrameBuffer)
        let gl = currentContext().gl
        v.mScreenFramebuffer = cast[GLuint](gl.getParami(gl.FRAMEBUFFER_BINDING))
        bindFramebuffer(gl, v.mActiveFrameBuffer)

proc getViewMatrix*(v: Viewport): Matrix4 =
    let cam = v.camera
    doAssert(not cam.isNil)
    var viewTransform = v.viewMatrix
    var projTransform : Transform3D
    cam.getProjectionMatrix(v.bounds, projTransform)
    result = projTransform * viewTransform

proc draw*(v: Viewport) =
    if v.rootNode.isNil: return

    let c = currentContext()
    v.prepareFramebuffers()

    c.withTransform v.getViewMatrix():
        v.rootNode.recursiveDraw()

proc rayWithScreenCoords*(v: Viewport, coords: Point): Ray =
    result.origin = v.camera.node.translation
    let x = (2.0 * coords.x) / v.bounds.width - 1.0
    let y = 1.0 - (2.0 * coords.y) / v.bounds.height
    let rayClip = newVector4(x, y, -1, 1)

    var proj : Transform3D
    v.mCamera.getProjectionMatrix(v.bounds, proj)

    proj.inverse()
    var rayEye = proj * rayClip
    rayEye[2] = -1
    rayEye[3] = 0

    var viewMat = v.mCamera.node.worldTransform

    rayEye = viewMat * rayEye
    result.direction = newVector3(rayEye[0], rayEye[1], rayEye[2])
    result.direction.normalize()

import opengl

proc aquireTempFramebuffer*(v: Viewport): SelfContainedImage =
    let vp = currentContext().gl.getViewport()
    let size = newSize(vp[2].Coord, vp[3].Coord)

    if not v.tempFramebuffers.isNil and v.tempFramebuffers.len > 0:
        result = v.tempFramebuffers[^1]
        v.tempFramebuffers.setLen(v.tempFramebuffers.len - 1)
        if result.size != size:
            echo "REALLOCATING TEMP BUFFER"
            result = imageWithSize(size)
    else:
        echo "CREATING TEMP BUFFER"
        result = imageWithSize(size)

proc releaseTempFramebuffer*(v: Viewport, fb: SelfContainedImage) =
    if v.tempFramebuffers.isNil:
        v.tempFramebuffers = newSeq[SelfContainedImage]()
    v.tempFramebuffers.add(fb)

proc swapCompositingBuffers*(v: Viewport) =
    assert(v.numberOfNodesWithBackCompositionInCurrentFrame > 0)
    dec v.numberOfNodesWithBackCompositionInCurrentFrame
    let boundsSize = v.bounds.size
    let c = currentContext()
    let gl = c.gl
    let vp = gl.getViewport()
    when defined(js):
        #proc ortho*(dest: var Matrix4, left, right, bottom, top, near, far: Coord) =
        var mat = ortho(0, cast[Coord](vp[2]), 0, cast[Coord](vp[3]), -1, 1)

        c.withTransform mat:
            if v.numberOfNodesWithBackCompositionInCurrentFrame == 0:
                gl.bindFramebuffer(gl.FRAMEBUFFER, v.mScreenFrameBuffer)
            else:
                gl.bindFramebuffer(gl.FRAMEBUFFER, v.mBackupFrameBuffer.framebuffer)
            c.drawImage(v.mActiveFrameBuffer, newRect(0, 0, cast[Coord](vp[2]), cast[Coord](vp[3])))
    else:
        if v.numberOfNodesWithBackCompositionInCurrentFrame == 0:
            # Swap active buffer to screen
            gl.bindFramebuffer(GL_READ_FRAMEBUFFER, v.mActiveFrameBuffer.framebuffer)
            gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER, v.mScreenFrameBuffer)
        else:
            # Swap active buffer to backup buffer
            gl.bindFramebuffer(GL_READ_FRAMEBUFFER, v.mActiveFrameBuffer.framebuffer)
            gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER, v.mBackupFrameBuffer.framebuffer)
        glBlitFramebuffer(0, 0, vp[2], vp[3], 0, 0, vp[2], vp[3], GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT, GL_NEAREST)

    swap(v.mActiveFrameBuffer, v.mBackupFrameBuffer)

proc addAnimation*(v: Viewport, a: Animation) = v.view.window.addAnimation(a)

proc addLightSource*(v: Viewport, ls: LightSource) =
    if v.lightSources.isNil():
        v.lightSources = newTable[string, LightSource]()
    if v.lightSources.len() < rod_types.maxLightsCount:
        v.lightSources[ls.node.name] = ls
    else:
        echo "Count of light sources is limited. Current count equals " & $rod_types.maxLightsCount

proc removeLightSource*(v: Viewport, ls: LightSource) =
    if v.lightSources.isNil() or v.lightSources.len() <= 0:
        echo "Current light sources count equals 0."
    else:
        v.lightSources.del(ls.node.name)

import component.all_components
