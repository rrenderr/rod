import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image
import nimx.matrixes

import rod.node
import rod.viewport

import rod.component

type Overlay* = ref object of OverlayComponent

var overlayComposition = newComposition """
uniform Image uBackground;
uniform Image uForeground;
uniform vec2 viewportSize;

vec2 fbUv(vec4 imgTexCoords) {
    return imgTexCoords.xy + (imgTexCoords.zw - imgTexCoords.xy) * (vPos / viewportSize);
}

void compose() {
    vec2 bgUv = fbUv(uBackground.texCoords);
    vec2 fgUv = fbUv(uForeground.texCoords);
    //vec2 uv = gl_FragCoord.xy / viewportSize * (uBackground.texCoords.zw);
    vec4 burnColor = texture2D(uBackground.tex, bgUv);
    vec4 maskColor = texture2D(uForeground.tex, fgUv);
    //burnColor *= 1.0 + maskColor.a * 2.0;
    //gl_FragColor = maskColor * 1.5;
    //gl_FragColor = vec4(0.0, 0, 1, 0.5);
    //gl_FragColor = vec4(1.0, 0, 0, 1.0);
    gl_FragColor = burnColor * (1.0 + maskColor.a * 2.0);
    //gl_FragColor = maskColor;
}
"""

method draw*(o: Overlay) =
    o.node.sceneView.swapCompositingBuffers()
    let c = currentContext()
    c.fillColor = blackColor()
    c.drawRect(newRect(200, 200, 50, 50))

    discard """
    let vp = o.node.sceneView
    let tmpBuf = vp.aquireTempFramebuffer()

    let c = currentContext()
    c.gl.bindFramebuffer(tmpBuf)

    c.gl.clearWithColor(0, 0, 0, 0)
    for c in o.node.children: c.recursiveDraw()

    vp.swapCompositingBuffers()
    echo "overlay"
    let vpbounds = c.gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    echo @vpbounds

    let o = ortho(vpbounds[0].Coord, vpbounds[2].Coord, vpbounds[3].Coord, vpbounds[1].Coord, -1, 1)

    c.withTransform o:
        overlayComposition.draw newRect(0, 0, vpbounds[2].Coord, vpbounds[3].Coord):
            setUniform("uBackground", vp.mBackupFrameBuffer)
            setUniform("uForeground", tmpBuf)
            setUniform("viewportSize", vpSize)

    vp.releaseTempFramebuffer(tmpBuf)
    """

method isPosteffectComponent*(c: Overlay): bool = false

registerComponent[Overlay]()
