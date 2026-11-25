import AppKit
import SceneKit
import simd

enum ChristmasTreeArt {
    private typealias Vector = SIMD3<Float>
    private typealias Color = SIMD4<Float>
    private static let up = Vector(0, 1, 0)

    private struct Mesh {
        var vertices: [Vector] = []
        var normals: [Vector] = []
        var colors: [Color] = []

        mutating func triangle(_ a: Vector, _ b: Vector, _ c: Vector, color: Color, upward: Bool = false) {
            let cross = simd_cross(b - a, c - a)
            guard simd_length_squared(cross) > 1e-12 else { return }
            var normal = simd_normalize(cross)
            if upward && normal.y < 0 { normal = -normal }
            vertices.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            colors.append(contentsOf: [color, color, color])
        }

        // The raised middle gives both the needles and the drifts a lit edge and a shaded side.
        mutating func leaf(from start: Vector, to tip: Vector, width: Float, color: Color) {
            let lateral = simd_cross(tip - start, ChristmasTreeArt.up)
            guard simd_length_squared(lateral) > 1e-8 else { return }
            let side = simd_normalize(lateral) * width
            let center = start + (tip - start) * 0.36
            let ridge = center + ChristmasTreeArt.up * (width * 0.52)
            triangle(start, center + side, ridge, color: color, upward: true)
            triangle(ridge, center + side, tip, color: color, upward: true)
            triangle(start, ridge, center - side, color: color, upward: true)
            triangle(ridge, tip, center - side, color: color, upward: true)
        }

        mutating func needle(from start: Vector, to tip: Vector, width: Float, color: Color) {
            let lateral = simd_cross(tip - start, ChristmasTreeArt.up)
            guard simd_length_squared(lateral) > 1e-8 else { return }
            let side = simd_normalize(lateral) * width
            triangle(start - side, start + side, tip, color: color, upward: true)
        }

        func node() -> SCNNode {
            let points = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
            let directions = normals.withUnsafeBufferPointer { Data(buffer: $0) }
            let pigments = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let indices = (0..<vertices.count).map(UInt32.init)
            let sources = [
                SCNGeometrySource(data: points, semantic: .vertex, vectorCount: vertices.count, usesFloatComponents: true,
                                  componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<Vector>.stride),
                SCNGeometrySource(data: directions, semantic: .normal, vectorCount: normals.count, usesFloatComponents: true,
                                  componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<Vector>.stride),
                SCNGeometrySource(data: pigments, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                  componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<Color>.stride),
            ]
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: sources, elements: [element])
            let finish = SCNMaterial()
            finish.lightingModel = .lambert
            finish.isDoubleSided = true
            geometry.firstMaterial = finish
            return SCNNode(geometry: geometry)
        }
    }

    static func buildScene(_ scene: SCNScene, ornament: Ornament) -> SCNNode {
        let root = scene.rootNode
        scene.lightingEnvironment.intensity = 0.35
        light(scene, type: .ambient, color: 0xa8bbc5, intensity: 340, at: SCNVector3Zero)
        light(scene, type: .directional, color: 0xfff3e2, intensity: 680, at: SCNVector3(-3, 5, 4))
        light(scene, type: .directional, color: 0xafd8f5, intensity: 310, at: SCNVector3(4, 3, -2))
        addBase(to: root)

        var rng = SnowRandom(state: 88_421)
        var needles = Mesh()
        var powder = Mesh()
        addCrown(to: &needles)
        let lamp = SCNSphere(radius: 0.027)
        lamp.segmentCount = 16
        lamp.firstMaterial = finish(0xffd28c, shine: 0.25)
        lamp.firstMaterial?.emission.contents = NSColor(rgb: 0xe29c44)
        lamp.firstMaterial?.emission.intensity = 0.23
        let glow = SCNPlane(width: 0.13, height: 0.13)
        glow.firstMaterial = transparentGlow(0xffb765, alpha: 0.19)
        let faceCamera = SCNBillboardConstraint()
        let hues = ornament.colors
        let baubles = hues.map { finish($0, shine: 0.22) }
        let cap = SCNCylinder(radius: 0.018, height: 0.025)
        cap.firstMaterial = finish(0xbb9862, shine: 0.28)

        let levels = 21
        for row in 0..<levels {
            let fraction = Float(row) / Float(levels - 1)
            let reach = 0.10 + 1.16 * pow(1 - fraction, 0.96)
            let level = 0.61 + 2.31 * fraction
            let branches = max(5, 12 - row / 3)
            for index in 0..<branches {
                let angle = Float(row) * 2.39996 + 2 * Float.pi * Float(index) / Float(branches) + random(-0.17, 0.17, &rng)
                let direction = Vector(cos(angle), 0, sin(angle))
                let lateral = Vector(-direction.z, 0, direction.x)
                let span = reach * random(0.86, 1.08, &rng)
                let start = direction * 0.052 + up * (level + random(-0.062, 0.062, &rng))
                let tip = start + direction * span + up * (-0.17 * (1 - fraction) + random(-0.028, 0.052, &rng))

                let interior = color(index.isMultiple(of: 2) ? 0x275241 : 0x32624a)
                let fresh = color(index.isMultiple(of: 3) ? 0x548f6b : 0x407f57)
                needles.leaf(from: start, to: tip, width: 0.075 * span, color: interior)
                addSprig(from: start, to: tip, spread: span * 0.19, baseColor: fresh, to: &needles, random: &rng)
                for offshoot in 0..<7 {
                    let position = 0.23 + Float(offshoot) * 0.105
                    let base = onBranch(from: start, to: tip, at: position)
                    let side: Float = offshoot.isMultiple(of: 2) ? 1 : -1
                    let length = span * (0.36 - position * 0.26) * random(0.91, 1.12, &rng)
                    let end = base + lateral * (length * side) + direction * (length * 0.83)
                        + up * (length * random(-0.32, 0.36, &rng))
                    let tint = offshoot.isMultiple(of: 3) ? color(0x5a9272) : fresh
                    addSprig(from: base, to: end, spread: length * 0.48, baseColor: tint, to: &needles, random: &rng)
                }

                if (row + index * 3).isMultiple(of: 7) {
                    let middle = onBranch(from: start, to: tip, at: 0.53) + up * (span * 0.057 + 0.02)
                    let end = onBranch(from: start, to: tip, at: 0.89) + up * (span * 0.052 + 0.014)
                    let width = max(0.017, span * 0.091)
                    powder.leaf(from: middle, to: end, width: width, color: color(0xc2d8d6))
                    powder.leaf(from: middle - lateral * (width * 0.50), to: end - lateral * (width * 0.67),
                                width: width * 0.38, color: color(0x8fb1b1))
                }
                if ornament.extras {
                    let point = onBranch(from: start, to: tip, at: 0.93)
                    if (index + 2 * row).isMultiple(of: 4) {
                        add(lamp, at: point + up * 0.021, to: root)
                        if point.z > 0.12 {
                            let halo = add(glow, at: point + Vector(0, 0.021, 0.02), to: root)
                            halo.constraints = [faceCamera]
                        }
                    } else if fraction < 0.80 && (index * 2 + row).isMultiple(of: 9) {
                        let radius = 0.055 + Float((index * 7 + row * 3) % 5) * 0.0045
                        let sphere = SCNSphere(radius: CGFloat(radius))
                        sphere.segmentCount = 24
                        sphere.firstMaterial = baubles[(index + row * 3) % baubles.count]
                        let center = point - up * 0.062
                        add(sphere, at: center, to: root)
                        add(cap, at: center + up * radius, to: root)
                    }
                }
            }
        }
        root.addChildNode(needles.node())
        root.addChildNode(powder.node())
        addStar(to: root)

        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.1
        camera.zFar = 25
        let view = SCNNode()
        view.camera = camera
        view.position = SCNVector3(0.24, 2.06, 6.25)
        view.look(at: SCNVector3(0, 1.65, 0))
        root.addChildNode(view)
        return view
    }

    private static func addCrown(to mesh: inout Mesh) {
        let rings = (0...15).map { row -> [Vector] in
            let t = Float(row) / 15
            return (0..<28).map { section in
                let angle = Float(section) * 2 * .pi / 28
                let uneven = 1 + 0.06 * sin(7 * angle + t * 18) + 0.03 * cos(11 * angle - 18 * t)
                let radius = (0.022 + 0.35 * pow(1 - t, 0.93)) * uneven
                return Vector(radius * cos(angle), 0.49 + 2.51 * t, radius * sin(angle))
            }
        }
        for row in 0..<(rings.count - 1) {
            for section in rings[row].indices {
                let next = (section + 1) % rings[row].count
                let tone = color((row + section).isMultiple(of: 3) ? 0x1d3b30 : 0x234034)
                mesh.triangle(rings[row][section], rings[row + 1][section], rings[row][next], color: tone)
                mesh.triangle(rings[row][next], rings[row + 1][section], rings[row + 1][next], color: tone)
            }
        }
    }

    private static func addSprig(from start: Vector, to tip: Vector, spread: Float, baseColor: Color,
                                 to mesh: inout Mesh, random rng: inout SnowRandom) {
        let direction = simd_normalize(tip - start)
        let lateral = simd_normalize(simd_cross(direction, up))
        let lifts: [Float] = [-0.56, 0.32, 1.30]
        let spreads: [Float] = [0.72, 1.10, 0.59]
        let pale = color(0x7fa684)
        mesh.leaf(from: start, to: tip, width: spread * 0.28, color: baseColor)
        for step in 0..<9 {
            let t = 0.12 + Float(step) * 0.092
            let base = onBranch(from: start, to: tip, at: t)
            let length = spread * (0.59 + 0.54 * sin(t * .pi)) * (1 - t * 0.61)
            for i in 0..<6 {
                let side: Float = i.isMultiple(of: 2) ? 1 : -1
                let delta = length * random(0.85, 1.26, &rng)
                let end = base + direction * (delta * 0.79) + lateral * (delta * side * spreads[i / 2])
                    + up * (delta * lifts[i / 2])
                let tint = simd_mix(baseColor, pale, Color(repeating: random(0, 0.25, &rng)))
                mesh.needle(from: base, to: end, width: max(0.002, delta * 0.125), color: tint)
            }
        }
    }

    private static func onBranch(from start: Vector, to tip: Vector, at t: Float) -> Vector {
        start + (tip - start) * t - up * (simd_distance(start, tip) * 0.059 * sin(.pi * t))
    }

    private static func addBase(to root: SCNNode) {
        let shade = SCNPlane(width: 1.55, height: 0.88)
        shade.firstMaterial = transparentGlow(0x0b1922, alpha: 0.62)
        let shadowNode = add(shade, at: Vector(0.10, 0.003, 0.12), to: root)
        shadowNode.eulerAngles.x = -.pi / 2

        let pot = SCNCone(topRadius: 0.294, bottomRadius: 0.239, height: 0.238)
        pot.radialSegmentCount = 48
        pot.firstMaterial = finish(0x695749, shine: 0.19)
        add(pot, at: Vector(0, 0.142, 0), to: root)
        let lip = SCNTorus(ringRadius: 0.277, pipeRadius: 0.017)
        lip.firstMaterial = finish(0xa28761, shine: 0.26)
        add(lip, at: Vector(0, 0.255, 0), to: root)
        let trunk = SCNCylinder(radius: 0.076, height: 0.52)
        trunk.firstMaterial = finish(0x49382c, shine: 0.05)
        add(trunk, at: Vector(0, 0.42, 0), to: root)
    }

    private static func addStar(to root: SCNNode) {
        let outline = NSBezierPath()
        for point in 0..<10 {
            let angle = CGFloat(point) * .pi / 5 + .pi / 2
            let r: CGFloat = point.isMultiple(of: 2) ? 0.205 : 0.094
            let vertex = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if point == 0 { outline.move(to: vertex) } else { outline.line(to: vertex) }
        }
        outline.close()
        let geometry = SCNShape(path: outline, extrusionDepth: 0.050)
        geometry.chamferRadius = 0.014
        geometry.firstMaterial = finish(0xdab877, shine: 0.30)
        geometry.firstMaterial?.emission.contents = NSColor(rgb: 0xffc576)
        geometry.firstMaterial?.emission.intensity = 0.12
        add(geometry, at: Vector(0, 3.07, 0.035), to: root)
    }

    private static func light(_ scene: SCNScene, type: SCNLight.LightType, color: UInt32, intensity: CGFloat,
                              at position: SCNVector3) {
        let light = SCNLight()
        light.type = type
        light.color = NSColor(rgb: color)
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        node.position = position
        if type != .ambient { node.look(at: SCNVector3(0, 1.25, 0)) }
        scene.rootNode.addChildNode(node)
    }

    @discardableResult
    private static func add(_ geometry: SCNGeometry, at point: Vector, to root: SCNNode) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(CGFloat(point.x), CGFloat(point.y), CGFloat(point.z))
        root.addChildNode(node)
        return node
    }

    private static func finish(_ rgb: UInt32, shine: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(rgb: rgb)
        material.specular.contents = NSColor(white: shine, alpha: 1)
        material.shininess = 0.35
        return material
    }

    private static func transparentGlow(_ rgb: UInt32, alpha: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = WinterArtwork.bitmap(width: 96, height: 96) { ink in
            ink.glow(48, 48, 48, rgb, alpha: alpha)
        }
        material.writesToDepthBuffer = false
        return material
    }

    private static func color(_ rgb: UInt32) -> Color {
        func channel(_ byte: UInt32) -> Float {
            let encoded = Float(byte & 255) / 255
            return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        return Color(channel(rgb >> 16), channel(rgb >> 8), channel(rgb), 1)
    }

    private static func random(_ low: Float, _ high: Float, _ rng: inout SnowRandom) -> Float {
        Float(rng.inRange(CGFloat(low), CGFloat(high)))
    }
}
