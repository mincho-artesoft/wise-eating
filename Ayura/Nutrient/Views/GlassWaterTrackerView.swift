import SwiftUI
import MetalKit
import simd
import Combine

// MARK: - Configuration, Math, Data Structures, Geometry, and Renderer

// --- MODIFICATION START ---
// Добавени са цветови константи за дъното на чашата за светла и тъмна тема.
private enum Config {
    static let metalDevice = MTLCreateSystemDefaultDevice()!
    static let msaaSampleCount: Int = 4
    static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm
    static let depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8
    static let cameraDistance: Float = 4.0
    static let maxWaterHeight: Float = 2.0
    static let panToStepThreshold: CGFloat = 15.0
    static let indexOfRefractionGlass: Float = 1.52
    static let indexOfRefractionWater: Float = 1.33
    
    // Цветове за стените
    static let glassColor = SIMD4<Float>(0.9, 0.95, 1.0, 0.3) // Тъмна тема
    static let lightThemeGlassColor = SIMD4<Float>(0.1, 0.05, 0, 0.55) // Светла тема
    
    // Цветове за дъното
    static let glassBottomColor = SIMD4<Float>(0.9, 0.95, 1.0, 0.3) // Тъмна тема
    static let lightThemeGlassBottomColor = SIMD4<Float>(0, 0, 0, 1) // Светла тема

    static let waterColor = SIMD4<Float>(0.75, 0.85, 0.95, 0.85)
    static let lightDirection: SIMD3<Float> = normalize([0.8, 1.0, -0.5])
    static let ambientLight: Float = 0.25
    static let specularIntensity: Float = 0.8
    static let shininessExponent: Float = 150.0
}
// --- MODIFICATION END ---

private func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 { let y_scale = 1.0 / tanf(fovy * 0.5); let x_scale = y_scale / aspectRatio; let z_range = farZ - nearZ; let z_scale = -(farZ + nearZ) / z_range; let wz_scale = -2.0 * farZ * nearZ / z_range; var P = matrix_float4x4(0.0); P.columns = ( SIMD4<Float>(x_scale, 0.0, 0.0, 0.0), SIMD4<Float>(0.0, y_scale, 0.0, 0.0), SIMD4<Float>(0.0, 0.0, z_scale, -1.0), SIMD4<Float>(0.0, 0.0, wz_scale, 0.0) ); return P }
private func matrix_look_at_right_hand(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 { let z = normalize(eye - center); let x = normalize(cross(up, z)); let y = cross(z, x); let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye)); var M = matrix_float4x4(0.0); M.columns = ( SIMD4<Float>(x.x, y.x, z.x, 0.0), SIMD4<Float>(x.y, y.y, z.y, 0.0), SIMD4<Float>(x.z, y.z, z.z, 0.0), SIMD4<Float>(t.x, t.y, t.z, 1.0) ); return M }
private func matrix_translation(_ t: SIMD3<Float>) -> matrix_float4x4 { var M = matrix_identity_float4x4; M.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1.0); return M }
private struct SceneVertex { var position: SIMD3<Float>; var normal: SIMD3<Float>; var texCoord: SIMD2<Float> }
private struct SceneUniforms { var modelMatrix: matrix_float4x4; var viewMatrix: matrix_float4x4; var projectionMatrix: matrix_float4x4; var normalMatrix: matrix_float3x3; var cameraPosition_worldSpace: SIMD3<Float> }
private struct MaterialUniforms { var color: SIMD4<Float>; var indexOfRefraction: Float; var specularIntensity: Float; var shininess: Float; var ambientLight: Float }

// --- MODIFICATION START ---
// Генераторът вече връща индексите за стените и капачките в отделни масиви.
private struct CylinderGenerator {
    static func createCylinder(radiusTop: Float, radiusBottom: Float, height: Float, segments: Int, isCapped: Bool) -> (vertices: [SceneVertex], wallIndices: [UInt32], topCapIndices: [UInt32], bottomCapIndices: [UInt32]) {
        var vertices: [SceneVertex] = []; var wallIndices: [UInt32] = []; var topCapIndices: [UInt32] = []; var bottomCapIndices: [UInt32] = []; let halfHeight = height / 2.0; let wallVertexStartIndex = UInt32(vertices.count)
        for i in 0...segments { let theta = Float(i) * 2.0 * .pi / Float(segments); let cosTheta = cos(theta); let sinTheta = sin(theta); let normal = normalize(SIMD3<Float>(cosTheta, 0, sinTheta)); vertices.append(SceneVertex(position: [radiusTop * cosTheta, halfHeight, radiusTop * sinTheta], normal: normal, texCoord: [Float(i) / Float(segments), 1.0])); vertices.append(SceneVertex(position: [radiusBottom * cosTheta, -halfHeight, radiusBottom * sinTheta], normal: normal, texCoord: [Float(i) / Float(segments), 0.0])) }
        for i in 0..<segments { let i0 = wallVertexStartIndex + UInt32(i * 2); let i1 = i0 + 1; let i2 = i0 + 2; let i3 = i0 + 3; wallIndices.append(contentsOf: [i0, i1, i2, i2, i1, i3]) }
        if isCapped {
            let topCapVertexStartIndex = UInt32(vertices.count); vertices.append(SceneVertex(position: [0, halfHeight, 0], normal: [0, 1, 0], texCoord: [0.5, 0.5]))
            for i in 0...segments { let theta = Float(i) * 2.0 * .pi / Float(segments); vertices.append(SceneVertex(position: [radiusTop * cos(theta), halfHeight, radiusTop * sin(theta)], normal: [0, 1, 0], texCoord: [cos(theta)*0.5+0.5, sin(theta)*0.5+0.5])) }
            for i in 0..<segments { let p1 = topCapVertexStartIndex + 1 + UInt32(i); let p2 = topCapVertexStartIndex + 1 + UInt32(i + 1); topCapIndices.append(contentsOf: [topCapVertexStartIndex, p1, p2]) }
            let bottomCapVertexStartIndex = UInt32(vertices.count); vertices.append(SceneVertex(position: [0, -halfHeight, 0], normal: [0, -1, 0], texCoord: [0.5, 0.5]))
            for i in 0...segments { let theta = Float(i) * 2.0 * .pi / Float(segments); vertices.append(SceneVertex(position: [radiusBottom * cos(theta), -halfHeight, radiusBottom * sin(theta)], normal: [0, -1, 0], texCoord: [cos(theta)*0.5+0.5, sin(theta)*0.5+0.5])) }
            for i in 0..<segments { let p1 = bottomCapVertexStartIndex + 1 + UInt32(i); let p2 = bottomCapVertexStartIndex + 1 + UInt32(i + 1); bottomCapIndices.append(contentsOf: [bottomCapVertexStartIndex, p2, p1]) }
        }
        return (vertices, wallIndices, topCapIndices, bottomCapIndices)
    }
}
// --- MODIFICATION END ---
private struct SphereGenerator {
    static func createSphere(radius: Float, segments: Int) -> (vertices: [SceneVertex], indices: [UInt32]) {
        var vertices: [SceneVertex] = []; var indices: [UInt32] = []
        for y in 0...segments { for x in 0...segments { let xSeg = Float(x)/Float(segments), ySeg = Float(y)/Float(segments); let pos = SIMD3<Float>(cos(xSeg * 2 * .pi) * sin(ySeg * .pi), cos(ySeg * .pi), sin(xSeg * 2 * .pi) * sin(ySeg * .pi)); vertices.append(SceneVertex(position: pos*radius, normal: pos, texCoord: [xSeg, ySeg])) } }
        for y in 0..<segments { for x in 0..<segments { let i1 = UInt32((y*(segments+1))+x), i2 = i1+1, i3 = UInt32(((y+1)*(segments+1))+x), i4 = i3+1; indices.append(contentsOf: [i1, i3, i2, i2, i3, i4]) } }
        return (vertices, indices)
    }
}
private class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice, commandQueue: MTLCommandQueue
    var glassPipelineState: MTLRenderPipelineState?, skyboxPipelineState: MTLRenderPipelineState?
    var depthState: MTLDepthStencilState?, cullBackDepthState: MTLDepthStencilState?, cullFrontDepthState: MTLDepthStencilState?
    
    // Geometry Buffers
    // --- MODIFICATION START ---
    // Буферите са разделени за стени и дъно.
    var glassOuterVB: MTLBuffer?
    var glassOuterWallIB: MTLBuffer?, glassOuterWallICount: Int = 0
    var glassOuterBottomCapIB: MTLBuffer?, glassOuterBottomCapICount: Int = 0
    // --- MODIFICATION END ---
    var glassInnerWallVB: MTLBuffer?, glassInnerWallIB: MTLBuffer?, glassInnerWallICount: Int = 0
    var waterVolumeVB: MTLBuffer?, waterVolumeIB: MTLBuffer?, waterVolumeICount: Int = 0
    var skyboxVB: MTLBuffer?, skyboxIB: MTLBuffer?, skyboxICount: Int = 0
    
    // Textures & State
    var environmentTexture: MTLTexture?
    var waterVolumeCenterY: Float = 0.0, glassInnerCenterY: Float = 0.0
    let fixedOrientation: simd_quatf = simd_quatf(angle: .pi/8.0, axis: [1,0,0])
    var targetWaterHeight: Float = 1.0
    var currentWaterHeight: Float = 1.0
    
    // --- MODIFICATION START ---
    // Добавени са пропъртита за съхранение на двата цвята, идващи от SwiftUI.
    var glassColor: SIMD4<Float> = Config.glassColor
    var glassBottomColor: SIMD4<Float> = Config.glassBottomColor
    // --- MODIFICATION END ---

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        buildGeometry()
        buildTextures()
        buildPipelineStates()
        buildDepthStencilStates()
    }

    func buildGeometry() {
        let glassHeight: Float = 2.2, glassTopRadius: Float = 1.0, glassBottomRadius: Float = 0.8, glassWallThickness: Float = 0.08, glassBaseThickness: Float = 0.2
        
        // --- MODIFICATION START ---
        // Използваме новия CylinderGenerator и пълним отделните буфери за стени и дъно.
        let glassOuter = CylinderGenerator.createCylinder(radiusTop: glassTopRadius, radiusBottom: glassBottomRadius, height: glassHeight, segments: 48, isCapped: true)
        glassOuterVB = device.makeBuffer(bytes: glassOuter.vertices, length: glassOuter.vertices.count * MemoryLayout<SceneVertex>.stride, options: .storageModeShared)
        glassOuterWallIB = device.makeBuffer(bytes: glassOuter.wallIndices, length: glassOuter.wallIndices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        glassOuterWallICount = glassOuter.wallIndices.count
        glassOuterBottomCapIB = device.makeBuffer(bytes: glassOuter.bottomCapIndices, length: glassOuter.bottomCapIndices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        glassOuterBottomCapICount = glassOuter.bottomCapIndices.count
        // --- MODIFICATION END ---
        
        let glassInnerTopRadius = glassTopRadius - glassWallThickness, glassInnerBottomRadius = glassBottomRadius - glassWallThickness
        let glassInnerHeight = glassHeight - glassBaseThickness
        self.glassInnerCenterY = glassBaseThickness / 2.0
        let glassInner = CylinderGenerator.createCylinder(radiusTop: glassInnerTopRadius, radiusBottom: glassInnerBottomRadius, height: glassInnerHeight, segments: 48, isCapped: false)
        glassInnerWallVB = device.makeBuffer(bytes: glassInner.vertices, length: glassInner.vertices.count * MemoryLayout<SceneVertex>.stride, options: .storageModeShared)
        glassInnerWallIB = device.makeBuffer(bytes: glassInner.wallIndices, length: glassInner.wallIndices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        glassInnerWallICount = glassInner.wallIndices.count
        
        let water = CylinderGenerator.createCylinder(radiusTop: glassInnerTopRadius, radiusBottom: glassInnerBottomRadius, height: glassInnerHeight, segments: 48, isCapped: true)
        waterVolumeVB = device.makeBuffer(length: water.vertices.count * MemoryLayout<SceneVertex>.stride, options: .storageModeShared)
        waterVolumeIB = device.makeBuffer(length: (water.wallIndices.count + water.topCapIndices.count + water.bottomCapIndices.count) * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        updateWaterGeometry()
        
        let skybox = SphereGenerator.createSphere(radius: 20.0, segments: 32)
        skyboxVB = device.makeBuffer(bytes: skybox.vertices, length: skybox.vertices.count * MemoryLayout<SceneVertex>.stride, options: .storageModeShared)
        skyboxIB = device.makeBuffer(bytes: skybox.indices, length: skybox.indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        skyboxICount = skybox.indices.count
    }

    func updateWaterGeometry() {
        let glassHeight: Float = 2.2, glassTopRadius: Float = 1.0, glassBottomRadius: Float = 0.8, glassWallThickness: Float = 0.08, glassBaseThickness: Float = 0.2
        let glassInnerTopRadius = glassTopRadius - glassWallThickness, glassInnerBottomRadius = glassBottomRadius - glassWallThickness
        let glassInnerHeight = glassHeight - glassBaseThickness; let waterFillHeight = currentWaterHeight; let innerGlassBottomY = -glassInnerHeight / 2.0; let waterTopY = innerGlassBottomY + waterFillHeight
        guard waterFillHeight > 0.01 && waterTopY <= (glassInnerHeight / 2.0) else { waterVolumeICount = 0; return }
        let t = (waterTopY - innerGlassBottomY) / glassInnerHeight; let waterTopRadius = glassInnerBottomRadius + t * (glassInnerTopRadius - glassInnerBottomRadius); let waterVolumeHeight = waterFillHeight; self.waterVolumeCenterY = innerGlassBottomY + (waterVolumeHeight / 2.0) + self.glassInnerCenterY
        let water = CylinderGenerator.createCylinder(radiusTop: waterTopRadius, radiusBottom: glassInnerBottomRadius, height: waterVolumeHeight, segments: 48, isCapped: true)
        let allWaterIndices = water.wallIndices + water.topCapIndices + water.bottomCapIndices
        waterVolumeVB?.contents().copyMemory(from: water.vertices, byteCount: water.vertices.count * MemoryLayout<SceneVertex>.stride)
        waterVolumeIB?.contents().copyMemory(from: allWaterIndices, byteCount: allWaterIndices.count * MemoryLayout<UInt32>.stride)
        waterVolumeICount = allWaterIndices.count
    }

    func buildTextures() {
        let w = 512, h = 512; let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false); texDesc.usage = [.shaderRead, .shaderWrite]; environmentTexture = device.makeTexture(descriptor: texDesc)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { let t = Float(y) / Float(h - 1); let c = mix(SIMD3<Float>(0.6, 0.8, 1.0), SIMD3<Float>(0.1, 0.2, 0.4), t: t); for x in 0..<w { let i = (y * w + x) * 4; pixels[i] = UInt8(c.z * 255); pixels[i+1] = UInt8(c.y * 255); pixels[i+2] = UInt8(c.x * 255); pixels[i+3] = 255 } }
        environmentTexture?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
    }

    func buildPipelineStates() {
        guard let lib = device.makeDefaultLibrary() else { fatalError("Could not create default Metal library") }
        let vDesc = MTLVertexDescriptor(); vDesc.attributes[0].format = .float3; vDesc.attributes[0].offset = 0; vDesc.attributes[0].bufferIndex = 0; vDesc.attributes[1].format = .float3; vDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride; vDesc.attributes[1].bufferIndex = 0; vDesc.attributes[2].format = .float2; vDesc.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride*2; vDesc.attributes[2].bufferIndex = 0; vDesc.layouts[0].stride = MemoryLayout<SceneVertex>.stride
        let glassDesc = MTLRenderPipelineDescriptor(); glassDesc.vertexFunction = lib.makeFunction(name: "vertexMain"); glassDesc.fragmentFunction = lib.makeFunction(name: "fragmentGlass"); glassDesc.vertexDescriptor = vDesc; glassDesc.colorAttachments[0].pixelFormat = Config.colorPixelFormat; glassDesc.depthAttachmentPixelFormat = Config.depthStencilPixelFormat; glassDesc.stencilAttachmentPixelFormat = Config.depthStencilPixelFormat; glassDesc.rasterSampleCount = Config.msaaSampleCount; glassDesc.colorAttachments[0].isBlendingEnabled = true; glassDesc.colorAttachments[0].rgbBlendOperation = .add; glassDesc.colorAttachments[0].alphaBlendOperation = .add; glassDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; glassDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha; glassDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha; glassDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let skyboxDesc = MTLRenderPipelineDescriptor(); skyboxDesc.vertexFunction = lib.makeFunction(name: "vertexMain"); skyboxDesc.fragmentFunction = lib.makeFunction(name: "fragmentSkybox"); skyboxDesc.vertexDescriptor = vDesc; skyboxDesc.colorAttachments[0].pixelFormat = Config.colorPixelFormat; skyboxDesc.depthAttachmentPixelFormat = Config.depthStencilPixelFormat; skyboxDesc.stencilAttachmentPixelFormat = Config.depthStencilPixelFormat; skyboxDesc.rasterSampleCount = Config.msaaSampleCount
        do { glassPipelineState = try device.makeRenderPipelineState(descriptor: glassDesc); skyboxPipelineState = try device.makeRenderPipelineState(descriptor: skyboxDesc) } catch { fatalError("Failed to create pipeline states: \(error)") }
    }

    func buildDepthStencilStates() {
        let dDesc = MTLDepthStencilDescriptor(); dDesc.depthCompareFunction = .less; dDesc.isDepthWriteEnabled = true; depthState = device.makeDepthStencilState(descriptor: dDesc)
        let cbDesc = MTLDepthStencilDescriptor(); cbDesc.depthCompareFunction = .less; cbDesc.isDepthWriteEnabled = true; cullBackDepthState = device.makeDepthStencilState(descriptor: cbDesc)
        let cfDesc = MTLDepthStencilDescriptor(); cfDesc.depthCompareFunction = .less; cfDesc.isDepthWriteEnabled = true; cullFrontDepthState = device.makeDepthStencilState(descriptor: cfDesc)
    }

    func updateSceneState() {
        if abs(targetWaterHeight - currentWaterHeight) > 0.001 { currentWaterHeight += (targetWaterHeight - currentWaterHeight) * 0.1; updateWaterGeometry() } else if (targetWaterHeight != currentWaterHeight) { currentWaterHeight = targetWaterHeight; updateWaterGeometry() }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        updateSceneState()
        guard let cmdBuffer = commandQueue.makeCommandBuffer(), let drawable = view.currentDrawable, let passDesc = view.currentRenderPassDescriptor else { return }
        let rotM=matrix_float4x4(fixedOrientation); let viewM=matrix_look_at_right_hand(eye:[0,0,Config.cameraDistance],center:[0,0,0],up:[0,1,0]); let projM=matrix_perspective_right_hand(fovyRadians: .pi/4,aspectRatio:Float(view.drawableSize.width/max(1,view.drawableSize.height)),nearZ:0.1,farZ:100); let camPos = viewM.inverse.columns.3.xyz
        
        if let glassEnc = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
            glassEnc.label="Glass & Water"
            glassEnc.setRenderPipelineState(glassPipelineState!)
            glassEnc.setFragmentTexture(environmentTexture,index:0)
            
            // --- MODIFICATION START ---
            // Създаваме два материала - един за стените и един за дъното.
            let glassWallUni = MaterialUniforms(color: self.glassColor, indexOfRefraction: Config.indexOfRefractionGlass, specularIntensity: Config.specularIntensity, shininess: Config.shininessExponent, ambientLight: Config.ambientLight)
            let glassBottomUni = MaterialUniforms(color: self.glassBottomColor, indexOfRefraction: Config.indexOfRefractionGlass, specularIntensity: Config.specularIntensity, shininess: Config.shininessExponent, ambientLight: Config.ambientLight)
            // --- MODIFICATION END ---
            
            glassEnc.setDepthStencilState(cullFrontDepthState); glassEnc.setCullMode(.front)
            // --- MODIFICATION START ---
            // Рисуваме стените и дъното с техните отделни материали и буфери.
            drawObject(encoder:glassEnc,modelMatrix:rotM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassWallUni,vb:glassOuterVB!,ib:glassOuterWallIB!,iCount:glassOuterWallICount)
            drawObject(encoder:glassEnc,modelMatrix:rotM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassBottomUni,vb:glassOuterVB!,ib:glassOuterBottomCapIB!,iCount:glassOuterBottomCapICount)
            // --- MODIFICATION END ---
            
            let innerTrans = matrix_translation([0, glassInnerCenterY, 0]); let innerModelM = rotM * innerTrans
            drawObject(encoder:glassEnc,modelMatrix:innerModelM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassWallUni,vb:glassInnerWallVB!,ib:glassInnerWallIB!,iCount:glassInnerWallICount)
            
            glassEnc.setDepthStencilState(cullBackDepthState); glassEnc.setCullMode(.back)
            if waterVolumeICount > 0 {
                let waterUni = MaterialUniforms(color:Config.waterColor,indexOfRefraction:Config.indexOfRefractionWater,specularIntensity:Config.specularIntensity*0.5,shininess:Config.shininessExponent*0.8,ambientLight:Config.ambientLight)
                let waterTrans = matrix_translation([0, waterVolumeCenterY, 0]); let waterModelM = rotM * waterTrans
                drawObject(encoder:glassEnc,modelMatrix:waterModelM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:waterUni,vb:waterVolumeVB!,ib:waterVolumeIB!,iCount:waterVolumeICount)
            }
            // --- MODIFICATION START ---
            // Повтаряме рисуването и за задната страна със съответните материали.
            drawObject(encoder:glassEnc,modelMatrix:rotM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassWallUni,vb:glassOuterVB!,ib:glassOuterWallIB!,iCount:glassOuterWallICount)
            drawObject(encoder:glassEnc,modelMatrix:rotM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassBottomUni,vb:glassOuterVB!,ib:glassOuterBottomCapIB!,iCount:glassOuterBottomCapICount)
            // --- MODIFICATION END ---
            drawObject(encoder:glassEnc,modelMatrix:innerModelM,viewMatrix:viewM,projectionMatrix:projM,cameraPos:camPos,material:glassWallUni,vb:glassInnerWallVB!,ib:glassInnerWallIB!,iCount:glassInnerWallICount)
            glassEnc.endEncoding()
        }
        cmdBuffer.present(drawable); cmdBuffer.commit()
    }
    
    private func drawObject(encoder e: MTLRenderCommandEncoder, modelMatrix m: matrix_float4x4, viewMatrix v: matrix_float4x4, projectionMatrix p: matrix_float4x4, cameraPos c: SIMD3<Float>, material mat: MaterialUniforms?, vb: MTLBuffer, ib: MTLBuffer, iCount: Int) { var sUniforms=SceneUniforms(modelMatrix:m,viewMatrix:v,projectionMatrix:p,normalMatrix:m.upperLeft3x3.inverse.transpose,cameraPosition_worldSpace:c); e.setVertexBytes(&sUniforms, length:MemoryLayout<SceneUniforms>.stride, index:1); if var material = mat { e.setFragmentBytes(&material, length:MemoryLayout<MaterialUniforms>.stride, index:1) }; e.setVertexBuffer(vb,offset:0,index:0); e.drawIndexedPrimitives(type:.triangle,indexCount:iCount,indexType:.uint32,indexBuffer:ib,indexBufferOffset:0) }
}

// MARK: - SwiftUI View Representable
private struct GlassMetalView: UIViewRepresentable {
    @Binding var waterLevel: Float
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    // --- MODIFICATION START ---
    // Добавени са параметри за двата цвята.
    let glassColor: SIMD4<Float>
    let glassBottomColor: SIMD4<Float>
    // --- MODIFICATION END ---
    let device: MTLDevice
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self, renderer: MetalRenderer(device: device)) }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.delegate = context.coordinator.renderer; mtkView.colorPixelFormat = Config.colorPixelFormat; mtkView.depthStencilPixelFormat = Config.depthStencilPixelFormat; mtkView.sampleCount = Config.msaaSampleCount; mtkView.enableSetNeedsDisplay = false; mtkView.isPaused = false; mtkView.autoResizeDrawable = true; mtkView.isOpaque = false; mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan)); mtkView.addGestureRecognizer(panGesture)
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap)); mtkView.addGestureRecognizer(tapGesture)
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.renderer.targetWaterHeight = self.waterLevel
        // --- MODIFICATION START ---
        // При всяка промяна от SwiftUI, задаваме новите цветове на рендъръра.
        context.coordinator.renderer.glassColor = self.glassColor
        context.coordinator.renderer.glassBottomColor = self.glassBottomColor
        // --- MODIFICATION END ---
    }
    
    class Coordinator: NSObject {
        var parent: GlassMetalView; var renderer: MetalRenderer; private var stepsAppliedInCurrentPan: Int = 0
        init(parent: GlassMetalView, renderer: MetalRenderer) { self.parent = parent; self.renderer = renderer; super.init() }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) { parent.onIncrement() }
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began: stepsAppliedInCurrentPan = 0
            case .changed: let translationY = gesture.translation(in: gesture.view).y; let totalSteps = Int(round(-translationY / Config.panToStepThreshold)); let newSteps = totalSteps - stepsAppliedInCurrentPan; if newSteps > 0 { for _ in 0..<newSteps { parent.onIncrement() } } else if newSteps < 0 { for _ in 0..<abs(newSteps) { parent.onDecrement() } }; if newSteps != 0 { stepsAppliedInCurrentPan = totalSteps }
            case .ended, .cancelled: stepsAppliedInCurrentPan = 0
            default: break
            }
        }
    }
}

// MARK: - Main SwiftUI View (The New Component)
struct GlassWaterTrackerView: View {
    @Binding var consumed: Int; let goal: Int; let onIncrement: () -> Void; let onDecrement: () -> Void
    @State private var waterLevel: Float = 0.0; private static var metalDevice: MTLDevice? = Config.metalDevice; @State private var updateWorkItem: DispatchWorkItem?
    
    @ObservedObject private var effectManager = EffectManager.shared
    
    var body: some View {
        Group {
            if let device = GlassWaterTrackerView.metalDevice {
                
                // --- MODIFICATION START ---
                // Изчисляваме кои цветове да използваме в зависимост от темата.
                let currentGlassColor = effectManager.isLightRowTextColor ? Config.glassColor : Config.lightThemeGlassColor
                let currentGlassBottomColor = effectManager.isLightRowTextColor ? Config.glassBottomColor : Config.lightThemeGlassBottomColor
                
                // Подаваме изчислените цветове на GlassMetalView.
                GlassMetalView(
                    waterLevel: $waterLevel,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                    glassColor: currentGlassColor,
                    glassBottomColor: currentGlassBottomColor,
                    device: device
                )
                // --- MODIFICATION END ---
                    .onAppear(perform: updateWaterLevel)
                    .onChange(of: consumed) { _, _ in triggerDebouncedUpdate() }
                    .onChange(of: goal) { _, _ in triggerDebouncedUpdate() }
            } else {
                ZStack { Circle().stroke(Color.gray, lineWidth: 4); Text("Metal\nError").font(.caption2).multilineTextAlignment(.center).foregroundColor(.gray) }
            }
        }
        .frame(width: 80, height: 80).clipShape(Circle())
    }
    private func triggerDebouncedUpdate() {
        updateWorkItem?.cancel()
        let newWorkItem = DispatchWorkItem { updateWaterLevel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: newWorkItem)
        self.updateWorkItem = newWorkItem
    }
    private func updateWaterLevel() {
        guard goal > 0 else { waterLevel = 0; return }
        let proportion = Float(consumed) / Float(goal)
        withAnimation(.easeOut(duration: 0.2)) { let newLevel = min(max(proportion, 0.0), 1.0) * Config.maxWaterHeight; self.waterLevel = newLevel }
    }
}

// MARK: - Helper Extensions
private extension SIMD4 { var xyz: SIMD3<Scalar> { return SIMD3<Scalar>(x, y, z) } }
private extension matrix_float4x4 { var upperLeft3x3: matrix_float3x3 { return matrix_float3x3(columns:(columns.0.xyz,columns.1.xyz,columns.2.xyz)) }; var inverse: matrix_float4x4 { return simd_inverse(self) }; var transpose: matrix_float4x4 { return simd_transpose(self) } }
private extension matrix_float3x3 { var inverse: matrix_float3x3 { return simd_inverse(self) }; var transpose: matrix_float3x3 { return simd_transpose(self) } }
