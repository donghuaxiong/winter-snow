import AppKit
import CoreGraphics
import Metal
import SceneKit

/// Native macOS SceneKit (Metal PBR) 3D renderer for refined desktop ornaments.
/// Renders offscreen at Retina resolution with physically based materials,
/// procedural micro-surface normal/roughness maps, warm/cool winter lighting,
/// and soft shadow-catcher contact shadows, then caches transparent CGImages
/// so DesktopEngine's 48px dirty-rect pipeline and window clipping stay fast.
enum Ornament3D {
    private static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private static let renderer: SCNRenderer? = {
        guard let device else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.autoenablesDefaultLighting = false
        r.isJitteringEnabled = false
        return r
    }()

    private static let lock = NSLock()
    private static let cache: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 64
        return c
    }()

    // MARK: - Procedural PBR Textures & Environment

    private static let environmentMap: CGImage? = makeWinterEnvironmentMap(width: 512, height: 256)
    private static let snowNormalMap: CGImage? = makeNoiseNormalMap(size: 256, scale: 1.0, strength: 1.8, seed: 101)
    private static let knitNormalMap: CGImage? = makeKnitNormalMap(size: 128)
    private static let feltNormalMap: CGImage? = makeNoiseNormalMap(size: 192, scale: 2.4, strength: 1.5, seed: 303)
    private static let paperNormalMap: CGImage? = makeLinenNormalMap(size: 128)
    private static let brushedNormalMap: CGImage? = makeBrushedNormalMap(size: 128)

    // MARK: - Public Drawing Entrypoints

    static func draw(_ ornament: Ornament, in size: CGSize, with ink: Ink) -> Bool {
        guard ornament.kind == .snowman || ornament.kind == .gift || ornament.kind == .tree else {
            return false
        }
        guard let image = image(for: ornament, logicalSize: size) else { return false }
        drawFlipped(image, in: CGRect(origin: .zero, size: size), with: ink)
        return true
    }

    static func drawSnowball(at center: CGPoint, radius: CGFloat, tone: Int, with ink: Ink) -> Bool {
        let key = "ball-\(tone % 3)" as NSString
        let image: CGImage?
        if let cached = cache.object(forKey: key) {
            image = cached
        } else {
            image = renderScene(pixelSize: CGSize(width: 192, height: 192)) { scene in
                let cam = setupCamera(in: scene, position: SCNVector3(0, 0.12, 3.05), lookAt: SCNVector3(0, 0, 0), fov: 38)
                setupLighting(in: scene, warmBoost: 0.7)
                let sphere = SCNSphere(radius: 0.88)
                sphere.segmentCount = 48
                sphere.firstMaterial = snowMaterial(tint: 0xF7FBFF)
                let node = SCNNode(geometry: sphere)
                node.eulerAngles = SCNVector3(CGFloat(tone) * 0.4, CGFloat(tone) * 1.1, 0)
                scene.rootNode.addChildNode(node)
                return cam
            }
            if let image { cache.setObject(image, forKey: key) }
        }
        guard let image else { return false }
        let pad = radius * 1.12
        drawFlipped(image, in: CGRect(x: center.x - pad, y: center.y - pad, width: pad * 2, height: pad * 2), with: ink)
        return true
    }

    // MARK: - Cache & Offscreen Snapshot

    private static func cacheKey(for ornament: Ornament, pixelSize: CGSize) -> NSString {
        let w = Int(pixelSize.width)
        let h = Int(pixelSize.height)
        switch ornament.kind {
        case .snowman:
            let c = ornament.costume
            let color = ornament.colors.first ?? 0xC92C48
            return "snowman-\(w)x\(h)-\(ornament.snowballs)-\(ornament.hat.rawValue)-\(c.face.rawValue)-\(c.scarf.rawValue)-\(c.arms)-\(c.buttons)-\(color)" as NSString
        case .gift:
            let color = ornament.colors.first ?? 0xFFD58F
            return "gift-\(w)x\(h)-\(ornament.palette.rawValue)-\(color)" as NSString
        case .tree:
            let cols = ornament.colors.map(String.init).joined(separator: ",")
            return "tree-\(w)x\(h)-\(ornament.extras)-\(cols)" as NSString
        default:
            return "\(ornament.kind.rawValue)-\(w)x\(h)" as NSString
        }
    }

    private static func image(for ornament: Ornament, logicalSize: CGSize) -> CGImage? {
        let scale: CGFloat = 2.5
        let pixelSize = CGSize(width: max(128, (logicalSize.width * scale).rounded()),
                               height: max(128, (logicalSize.height * scale).rounded()))
        let key = cacheKey(for: ornament, pixelSize: pixelSize)
        if let cached = cache.object(forKey: key) { return cached }

        let rendered: CGImage?
        switch ornament.kind {
        case .snowman:
            rendered = renderScene(pixelSize: pixelSize) { buildSnowmanScene($0, ornament: ornament) }
        case .gift:
            rendered = renderScene(pixelSize: pixelSize) { buildGiftScene($0, ornament: ornament) }
        case .tree:
            rendered = renderScene(pixelSize: pixelSize) { ChristmasTreeArt.buildScene($0, ornament: ornament) }
        default:
            rendered = nil
        }
        if let rendered { cache.setObject(rendered, forKey: key) }
        return rendered
    }

    private static func renderScene(pixelSize: CGSize, build: (SCNScene) -> SCNNode) -> CGImage? {
        guard let renderer else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        if let env = environmentMap {
            scene.lightingEnvironment.contents = env
            scene.lightingEnvironment.intensity = 1.15
        }
        let cameraNode = build(scene)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let nsImage = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        var rect = CGRect(origin: .zero, size: pixelSize)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func drawFlipped(_ image: CGImage, in rect: CGRect, with ink: Ink) {
        ink.ctx.saveGState()
        ink.ctx.translateBy(x: rect.minX, y: rect.maxY)
        ink.ctx.scaleBy(x: 1, y: -1)
        ink.ctx.interpolationQuality = .high
        ink.ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ink.ctx.restoreGState()
    }

    // MARK: - Common Scene Rig

    @discardableResult
    private static func setupCamera(in scene: SCNScene, position: SCNVector3, lookAt target: SCNVector3, fov: CGFloat) -> SCNNode {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = fov
        camera.zNear = 0.1
        camera.zFar = 50
        camera.wantsHDR = true
        camera.exposureOffset = 0.12
        camera.minimumExposure = -1.0
        camera.maximumExposure = 2.0
        cameraNode.camera = camera
        cameraNode.position = position
        cameraNode.look(at: target)
        scene.rootNode.addChildNode(cameraNode)
        return cameraNode
    }

    private static func setupLighting(in scene: SCNScene, warmBoost: CGFloat = 1.0) {
        // Key light: crisp cool winter moonlight from upper-left-front
        let key = SCNLight()
        key.type = .directional
        key.color = NSColor(rgb: 0xEFF6FF)
        key.intensity = 920
        key.castsShadow = true
        key.shadowColor = NSColor(srgbRed: 0.04, green: 0.10, blue: 0.22, alpha: 0.46)
        key.shadowRadius = 7.5
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.orthographicScale = 4.5
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-4.2, 6.8, 5.2)
        keyNode.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(keyNode)

        // Warm cabin-glow rim light from right-bottom-side
        let rim = SCNLight()
        rim.type = .directional
        rim.color = NSColor(rgb: 0xFFD093)
        rim.intensity = 460 * warmBoost
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(5.0, 2.0, 2.2)
        rimNode.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(rimNode)

        // Cool ambient sky bounce so shadows stay icy blue instead of muddy gray
        let fill = SCNLight()
        fill.type = .directional
        fill.color = NSColor(rgb: 0x9BC7F0)
        fill.intensity = 240
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-3.0, -1.5, 4.0)
        fillNode.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(fillNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(rgb: 0x99B7D6)
        ambient.intensity = 175
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private static func addShadowFloor(to scene: SCNScene, size: CGFloat = 10, y: CGFloat = 0) {
        let floor = SCNPlane(width: size, height: size)
        let mat = SCNMaterial()
        mat.lightingModel = .shadowOnly
        mat.writesToDepthBuffer = false
        floor.firstMaterial = mat
        let node = SCNNode(geometry: floor)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, y, 0)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    // MARK: - PBR Material Factories

    private static func snowMaterial(tint: UInt32 = 0xF5FAFF) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: tint)
        m.roughness.contents = 0.89
        m.metalness.contents = 0.0
        if let n = snowNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.42
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(2.5, 2.5, 1)
        }
        return m
    }

    private static func knitMaterial(_ rgb: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.96
        m.metalness.contents = 0.0
        if let n = knitNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.72
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(4.0, 4.0, 1)
        }
        return m
    }

    private static func feltMaterial(_ rgb: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.95
        m.metalness.contents = 0.0
        if let n = feltNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.45
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(2.0, 2.0, 1)
        }
        return m
    }

    private static func paperMaterial(_ rgb: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.86
        m.metalness.contents = 0.0
        if let n = paperNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.32
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(3.0, 3.0, 1)
        }
        return m
    }

    private static func satinRibbonMaterial(_ rgb: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.30
        m.metalness.contents = 0.45
        if let n = brushedNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.22
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
        }
        return m
    }

    private static func brassMaterial(_ rgb: UInt32 = 0xD8B064) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.26
        m.metalness.contents = 0.86
        if let n = brushedNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.28
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
        }
        return m
    }

    private static func woodMaterial(_ rgb: UInt32 = 0x513729) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.90
        m.metalness.contents = 0.0
        if let n = brushedNormalMap {
            m.normal.contents = n
            m.normal.intensity = 0.48
        }
        return m
    }

    private static func matteBaubleMaterial(_ rgb: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(rgb: rgb)
        m.roughness.contents = 0.34
        m.metalness.contents = 0.35
        return m
    }

    // MARK: - 1. 3D Snowman Scene

    private static func buildSnowmanScene(_ scene: SCNScene, ornament: Ornament) -> SCNNode {
        setupLighting(in: scene, warmBoost: 1.05)
        addShadowFloor(to: scene, size: 8, y: 0)

        let root = SCNNode()
        // Subtle 3/4 turn gives authentic 3D depth to nose, scarf tail, and hat brim
        root.eulerAngles.y = -0.14
        scene.rootNode.addChildNode(root)

        let snow = snowMaterial(tint: 0xF5FAFF)
        let twoBall = ornament.snowballs == 2

        let r0: CGFloat = 0.72
        let r1: CGFloat = 0.53
        let r2: CGFloat = 0.40
        let y0: CGFloat = r0 * 0.88
        let y1: CGFloat = twoBall ? y0 : y0 + (r0 + r1) * 0.74
        let yHead: CGFloat = twoBall ? y0 + (r0 + r2) * 0.76 : y1 + (r1 + r2) * 0.74

        func addSnowball(radius: CGFloat, y: CGFloat, squash: CGFloat) {
            let geom = SCNSphere(radius: radius)
            geom.segmentCount = 48
            geom.firstMaterial = snow
            let node = SCNNode(geometry: geom)
            node.position = SCNVector3(0, y, 0)
            node.scale = SCNVector3(1, squash, 1)
            root.addChildNode(node)
        }

        addSnowball(radius: r0, y: y0, squash: 0.90)
        if !twoBall { addSnowball(radius: r1, y: y1, squash: 0.93) }
        addSnowball(radius: r2, y: yHead, squash: 0.95)

        let bodyY = twoBall ? y0 : y1
        let bodyR = twoBall ? r0 : r1

        // Wooden buttons
        if ornament.costume.buttons {
            let btnMat = woodMaterial(0x362A24)
            btnMat.roughness.contents = 0.62
            let offsets: [CGFloat] = twoBall ? [0.16, -0.06, -0.28] : [0.16, -0.02, -0.20]
            for (idx, dy) in offsets.enumerated() {
                let z = sqrt(max(0.01, bodyR * bodyR - dy * dy)) * 0.97
                let cyl = SCNCylinder(radius: 0.052 - CGFloat(idx) * 0.003, height: 0.032)
                cyl.firstMaterial = btnMat
                let btn = SCNNode(geometry: cyl)
                btn.position = SCNVector3(sin(CGFloat(idx)) * 0.015, bodyY + dy, z)
                btn.eulerAngles.x = .pi / 2 - dy * 0.7
                root.addChildNode(btn)
            }
        }

        // Branching twig arms
        if ornament.costume.arms {
            let bark = woodMaterial(0x523728)
            for side: CGFloat in [-1, 1] {
                let armRoot = SCNNode()
                armRoot.position = SCNVector3(side * (bodyR * 0.82), bodyY + 0.08, 0.02)
                armRoot.eulerAngles.z = side * -0.52
                armRoot.eulerAngles.y = side * 0.16

                let main = SCNCylinder(radius: 0.030, height: 0.68)
                main.firstMaterial = bark
                let mainNode = SCNNode(geometry: main)
                mainNode.position = SCNVector3(0, 0.30, 0)
                armRoot.addChildNode(mainNode)

                let twig1 = SCNCylinder(radius: 0.018, height: 0.24)
                twig1.firstMaterial = bark
                let t1 = SCNNode(geometry: twig1)
                t1.position = SCNVector3(side * 0.07, 0.56, 0)
                t1.eulerAngles.z = side * -0.58
                armRoot.addChildNode(t1)

                let twig2 = SCNCylinder(radius: 0.016, height: 0.20)
                twig2.firstMaterial = bark
                let t2 = SCNNode(geometry: twig2)
                t2.position = SCNVector3(-side * 0.06, 0.48, 0.02)
                t2.eulerAngles.z = side * 0.62
                armRoot.addChildNode(t2)

                root.addChildNode(armRoot)
            }
        }

        // Knitted scarf
        let neckY = yHead - r2 * 0.80
        addSnowmanScarf(ornament.costume.scarf, palette: ornament.colors[0], at: neckY, neckRadius: r2 * 0.86, to: root)

        // Face
        addSnowmanFace(ornament.costume.face, headY: yHead, headR: r2, to: root)

        // Hat
        let hatY = yHead + r2 * 0.82
        addSnowmanHat(ornament.hat, accent: ornament.colors[0], at: hatY, headR: r2, to: root)

        // Frame camera so y = 0 lands near baseline (150/160 = 93.75% down)
        let centerY: CGFloat = twoBall ? 1.15 : 1.48
        let dist: CGFloat = twoBall ? 4.45 : 5.25
        return setupCamera(in: scene, position: SCNVector3(0.0, centerY + 0.35, dist), lookAt: SCNVector3(0, centerY - 0.08, 0), fov: 36)
    }

    private static func addSnowmanFace(_ face: SnowmanFace, headY: CGFloat, headR: CGFloat, to root: SCNNode) {
        guard face != .plain else { return }
        let coal = SCNMaterial()
        coal.lightingModel = .physicallyBased
        coal.diffuse.contents = NSColor(rgb: 0x1E2630)
        coal.roughness.contents = 0.42
        coal.metalness.contents = 0.05

        let eyeY = headY + 0.07
        let eyeZ = headR * 0.92
        if face == .smile {
            for side: CGFloat in [-1, 1] {
                let eye = SCNSphere(radius: 0.042)
                eye.firstMaterial = coal
                let node = SCNNode(geometry: eye)
                node.position = SCNVector3(side * 0.135, eyeY, eyeZ)
                root.addChildNode(node)
            }
        } else {
            let curve: CGFloat = face == .happy ? 0.35 : -0.35
            for side: CGFloat in [-1, 1] {
                let bar = SCNCapsule(capRadius: 0.018, height: 0.095)
                bar.firstMaterial = coal
                let node = SCNNode(geometry: bar)
                node.position = SCNVector3(side * 0.135, eyeY, eyeZ)
                node.eulerAngles = SCNVector3(0, side * 0.25, .pi / 2 + side * curve)
                root.addChildNode(node)
            }
        }

        // Soft blush cheeks
        let blush = feltMaterial(0xF0A6A8)
        blush.roughness.contents = 0.96
        for side: CGFloat in [-1, 1] {
            let cheek = SCNSphere(radius: 0.055)
            cheek.firstMaterial = blush
            let node = SCNNode(geometry: cheek)
            node.scale = SCNVector3(1.15, 0.72, 0.25)
            node.position = SCNVector3(side * 0.21, headY - 0.02, headR * 0.84)
            node.eulerAngles.y = side * 0.45
            root.addChildNode(node)
        }

        // Sculpted 3D carrot nose
        let carrotMat = feltMaterial(0xE87A35)
        carrotMat.roughness.contents = 0.78
        let carrot = SCNCone(topRadius: 0.008, bottomRadius: 0.056, height: 0.28)
        carrot.firstMaterial = carrotMat
        let nose = SCNNode(geometry: carrot)
        nose.position = SCNVector3(0.015, headY - 0.01, headR + 0.08)
        nose.eulerAngles = SCNVector3(.pi / 2 - 0.10, 0.14, 0)
        root.addChildNode(nose)

        // Smile pebbles
        if face == .sleepy {
            let mouth = SCNSphere(radius: 0.028)
            mouth.firstMaterial = coal
            let mNode = SCNNode(geometry: mouth)
            mNode.position = SCNVector3(0, headY - 0.14, headR * 0.92)
            root.addChildNode(mNode)
        } else {
            for index in 0..<5 {
                let t = CGFloat(index - 2)
                let dot = SCNSphere(radius: 0.020)
                dot.firstMaterial = coal
                let dNode = SCNNode(geometry: dot)
                let x = t * 0.055
                let y = headY - 0.165 + t * t * 0.014
                let z = sqrt(max(0.01, headR * headR - x * x - (y - headY) * (y - headY))) * 0.99
                dNode.position = SCNVector3(x, y, z)
                root.addChildNode(dNode)
            }
        }
    }

    private static func addSnowmanScarf(_ scarf: SnowmanScarf, palette: UInt32, at y: CGFloat, neckRadius: CGFloat, to root: SCNNode) {
        guard scarf != .none else { return }
        let color: UInt32
        switch scarf {
        case .red: color = 0xB82A3E
        case .blue: color = 0x2F6B9E
        case .green: color = 0x236854
        case .plaid: color = 0x7A4256
        default: color = palette
        }
        let mat = knitMaterial(color)

        let collar = SCNTorus(ringRadius: neckRadius * 1.02, pipeRadius: 0.105)
        collar.ringSegmentCount = 42
        collar.pipeSegmentCount = 20
        collar.firstMaterial = mat
        let collarNode = SCNNode(geometry: collar)
        collarNode.position = SCNVector3(0, y, 0.01)
        collarNode.scale = SCNVector3(1.0, 0.85, 1.0)
        root.addChildNode(collarNode)

        // Draped hanging scarf tail
        let tail = SCNBox(width: 0.18, height: 0.44, length: 0.075, chamferRadius: 0.032)
        tail.firstMaterial = mat
        let tailNode = SCNNode(geometry: tail)
        tailNode.position = SCNVector3(0.20, y - 0.24, neckRadius * 0.88)
        tailNode.eulerAngles = SCNVector3(-0.22, 0.34, 0.14)
        root.addChildNode(tailNode)

        // Subtle fringe tassels
        let fringeMat = knitMaterial(scarf == .plaid ? 0xE6B985 : color)
        for i in -2...2 {
            let f = SCNCapsule(capRadius: 0.012, height: 0.09)
            f.firstMaterial = fringeMat
            let fNode = SCNNode(geometry: f)
            fNode.position = SCNVector3(CGFloat(i) * 0.032, -0.24, 0)
            tailNode.addChildNode(fNode)
        }
    }

    private static func addSnowmanHat(_ hat: Hat, accent: UInt32, at y: CGFloat, headR: CGFloat, to root: SCNNode) {
        guard hat != .none else { return }
        let holder = SCNNode()
        holder.position = SCNVector3(0, y, 0)
        holder.eulerAngles.z = -0.05 // charming slight tilt
        root.addChildNode(holder)

        switch hat {
        case .top:
            let felt = feltMaterial(0x282E3A)
            let brim = SCNCylinder(radius: headR * 1.18, height: 0.055)
            brim.firstMaterial = felt
            let brimNode = SCNNode(geometry: brim)
            holder.addChildNode(brimNode)

            let crown = SCNCylinder(radius: headR * 0.78, height: 0.48)
            crown.firstMaterial = felt
            let crownNode = SCNNode(geometry: crown)
            crownNode.position = SCNVector3(0, 0.24, 0)
            holder.addChildNode(crownNode)

            let band = SCNCylinder(radius: headR * 0.80, height: 0.10)
            band.firstMaterial = satinRibbonMaterial(accent)
            let bandNode = SCNNode(geometry: band)
            bandNode.position = SCNVector3(0, 0.08, 0)
            holder.addChildNode(bandNode)

        case .knit:
            let mainMat = knitMaterial(0x2E74B3)
            let cuffMat = knitMaterial(0xDDEAF5)
            let dome = SCNSphere(radius: headR * 0.94)
            dome.firstMaterial = mainMat
            let domeNode = SCNNode(geometry: dome)
            domeNode.scale = SCNVector3(1.0, 0.92, 1.0)
            domeNode.position = SCNVector3(0, 0.08, 0)
            holder.addChildNode(domeNode)

            let cuff = SCNTorus(ringRadius: headR * 0.88, pipeRadius: 0.095)
            cuff.firstMaterial = cuffMat
            let cuffNode = SCNNode(geometry: cuff)
            cuffNode.position = SCNVector3(0, 0.02, 0)
            holder.addChildNode(cuffNode)

            let pom = SCNSphere(radius: 0.12)
            pom.firstMaterial = feltMaterial(0xF6F8FA)
            let pomNode = SCNNode(geometry: pom)
            pomNode.position = SCNVector3(0, headR * 0.96, 0)
            holder.addChildNode(pomNode)

        case .santa:
            let redFelt = feltMaterial(0xBA283D)
            let whitePlush = feltMaterial(0xF5F3EE)
            let trim = SCNTorus(ringRadius: headR * 0.92, pipeRadius: 0.095)
            trim.firstMaterial = whitePlush
            holder.addChildNode(SCNNode(geometry: trim))

            let cone = SCNCone(topRadius: 0.05, bottomRadius: headR * 0.88, height: 0.62)
            cone.firstMaterial = redFelt
            let coneNode = SCNNode(geometry: cone)
            coneNode.position = SCNVector3(0.08, 0.28, -0.02)
            coneNode.eulerAngles.z = -0.28
            holder.addChildNode(coneNode)

            let tip = SCNCone(topRadius: 0.03, bottomRadius: 0.09, height: 0.28)
            tip.firstMaterial = redFelt
            let tipNode = SCNNode(geometry: tip)
            tipNode.position = SCNVector3(0.28, 0.44, -0.02)
            tipNode.eulerAngles.z = -1.25
            holder.addChildNode(tipNode)

            let pom = SCNSphere(radius: 0.11)
            pom.firstMaterial = whitePlush
            let pomNode = SCNNode(geometry: pom)
            pomNode.position = SCNVector3(0.42, 0.36, -0.02)
            holder.addChildNode(pomNode)

        case .crown:
            let gold = brassMaterial(0xE8B952)
            let ring = SCNTorus(ringRadius: headR * 0.72, pipeRadius: 0.075)
            ring.firstMaterial = gold
            holder.addChildNode(SCNNode(geometry: ring))
            for i in 0..<6 {
                let a = CGFloat(i) * .pi * 2 / 6
                let spike = SCNCone(topRadius: 0.015, bottomRadius: 0.085, height: 0.28)
                spike.firstMaterial = gold
                let sNode = SCNNode(geometry: spike)
                sNode.position = SCNVector3(cos(a) * headR * 0.70, 0.14, sin(a) * headR * 0.70)
                holder.addChildNode(sNode)
            }
            let gem = SCNSphere(radius: 0.055)
            gem.firstMaterial = matteBaubleMaterial(0xD83B4A)
            let gemNode = SCNNode(geometry: gem)
            gemNode.position = SCNVector3(0, 0.06, headR * 0.78)
            holder.addChildNode(gemNode)

        case .cowboy:
            let suede = feltMaterial(0x9C633B)
            let brim = SCNCylinder(radius: headR * 1.42, height: 0.045)
            brim.firstMaterial = suede
            let brimNode = SCNNode(geometry: brim)
            brimNode.scale = SCNVector3(1.0, 1.0, 0.88)
            holder.addChildNode(brimNode)

            let crown = SCNCapsule(capRadius: headR * 0.68, height: 0.50)
            crown.firstMaterial = suede
            let crownNode = SCNNode(geometry: crown)
            crownNode.position = SCNVector3(0, 0.14, 0)
            holder.addChildNode(crownNode)

            let band = SCNCylinder(radius: headR * 0.71, height: 0.07)
            band.firstMaterial = woodMaterial(0x4E3226)
            let bandNode = SCNNode(geometry: band)
            bandNode.position = SCNVector3(0, 0.05, 0)
            holder.addChildNode(bandNode)

        case .party:
            let cone = SCNCone(topRadius: 0.02, bottomRadius: headR * 0.78, height: 0.65)
            cone.firstMaterial = feltMaterial(0x8D5FB8)
            let cNode = SCNNode(geometry: cone)
            cNode.position = SCNVector3(0, 0.30, 0)
            holder.addChildNode(cNode)
            let pom = SCNSphere(radius: 0.085)
            pom.firstMaterial = feltMaterial(0xF6B6CA)
            let pNode = SCNNode(geometry: pom)
            pNode.position = SCNVector3(0, 0.64, 0)
            holder.addChildNode(pNode)

        case .earmuffs, .headphones:
            let bandMat = hat == .earmuffs ? feltMaterial(0x7C4765) : brassMaterial(0x364B66)
            let padMat = hat == .earmuffs ? feltMaterial(0xEB8CA8) : satinRibbonMaterial(0x3D80A8)
            let arch = SCNTorus(ringRadius: headR * 1.06, pipeRadius: 0.042)
            arch.firstMaterial = bandMat
            let archNode = SCNNode(geometry: arch)
            archNode.position = SCNVector3(0, -headR * 0.80, 0)
            archNode.eulerAngles.x = .pi / 2
            holder.addChildNode(archNode)
            for side: CGFloat in [-1, 1] {
                let pad = SCNSphere(radius: 0.14)
                pad.firstMaterial = padMat
                let pNode = SCNNode(geometry: pad)
                pNode.scale = SCNVector3(0.7, 1.1, 1.0)
                pNode.position = SCNVector3(side * headR * 1.02, -headR * 0.82, 0)
                holder.addChildNode(pNode)
            }

        case .viking:
            let steel = brassMaterial(0x9BB0BE)
            steel.roughness.contents = 0.38
            let dome = SCNSphere(radius: headR * 0.94)
            dome.firstMaterial = steel
            let dNode = SCNNode(geometry: dome)
            dNode.scale = SCNVector3(1.0, 0.72, 1.0)
            dNode.position = SCNVector3(0, 0.04, 0)
            holder.addChildNode(dNode)
            let band = SCNCylinder(radius: headR * 0.96, height: 0.10)
            band.firstMaterial = brassMaterial(0xB8874D)
            holder.addChildNode(SCNNode(geometry: band))
            let hornMat = feltMaterial(0xF5E7CA)
            hornMat.roughness.contents = 0.62
            for side: CGFloat in [-1, 1] {
                let horn = SCNCone(topRadius: 0.015, bottomRadius: 0.085, height: 0.42)
                horn.firstMaterial = hornMat
                let hNode = SCNNode(geometry: horn)
                hNode.position = SCNVector3(side * (headR + 0.10), 0.18, 0)
                hNode.eulerAngles.z = side * -0.78
                holder.addChildNode(hNode)
            }

        case .elf:
            let green = feltMaterial(0x28825B)
            let trim = SCNTorus(ringRadius: headR * 0.90, pipeRadius: 0.08)
            trim.firstMaterial = feltMaterial(0xC23B55)
            holder.addChildNode(SCNNode(geometry: trim))
            let cone = SCNCone(topRadius: 0.03, bottomRadius: headR * 0.86, height: 0.68)
            cone.firstMaterial = green
            let cNode = SCNNode(geometry: cone)
            cNode.position = SCNVector3(0.08, 0.30, 0)
            cNode.eulerAngles.z = -0.32
            holder.addChildNode(cNode)
            let bell = SCNSphere(radius: 0.075)
            bell.firstMaterial = brassMaterial(0xF0C562)
            let bNode = SCNNode(geometry: bell)
            bNode.position = SCNVector3(0.24, 0.62, 0)
            holder.addChildNode(bNode)

        case .antlers:
            let band = SCNTorus(ringRadius: headR * 0.84, pipeRadius: 0.045)
            band.firstMaterial = feltMaterial(0xA6414B)
            holder.addChildNode(SCNNode(geometry: band))
            let antlerMat = woodMaterial(0x8C5835)
            for side: CGFloat in [-1, 1] {
                let stem = SCNCylinder(radius: 0.036, height: 0.56)
                stem.firstMaterial = antlerMat
                let sNode = SCNNode(geometry: stem)
                sNode.position = SCNVector3(side * 0.24, 0.26, 0)
                sNode.eulerAngles.z = side * -0.30
                holder.addChildNode(sNode)
                let fork = SCNCylinder(radius: 0.024, height: 0.28)
                fork.firstMaterial = antlerMat
                let fNode = SCNNode(geometry: fork)
                fNode.position = SCNVector3(side * 0.10, 0.08, 0)
                fNode.eulerAngles.z = side * -0.65
                sNode.addChildNode(fNode)
            }

        case .pirate:
            let dark = feltMaterial(0x202430)
            let brim = SCNBox(width: headR * 2.5, height: 0.34, length: headR * 1.4, chamferRadius: 0.14)
            brim.firstMaterial = dark
            let bNode = SCNNode(geometry: brim)
            bNode.position = SCNVector3(0, 0.14, 0)
            holder.addChildNode(bNode)
            let trim = SCNBox(width: headR * 2.1, height: 0.04, length: 0.06, chamferRadius: 0.015)
            trim.firstMaterial = brassMaterial(0xDFB668)
            let tNode = SCNNode(geometry: trim)
            tNode.position = SCNVector3(0, 0.04, headR * 0.70)
            holder.addChildNode(tNode)

        case .none:
            break
        }
    }

    // MARK: - 2. 3D Gift Box Scene

    private static func buildGiftScene(_ scene: SCNScene, ornament: Ornament) -> SCNNode {
        setupLighting(in: scene, warmBoost: 1.1)
        addShadowFloor(to: scene, size: 8, y: 0)

        let root = SCNNode()
        root.eulerAngles.y = 0.42 // 3/4 view showing front + side + top bow
        scene.rootNode.addChildNode(root)

        // Harmonized matte luxury paper + satin ribbon colors
        let (boxRGB, lidRGB, ribbonRGB): (UInt32, UInt32, UInt32) = {
            switch ornament.palette {
            case .winter: return (0x2D516C, 0x386484, 0xDDEEF9)
            case .classic: return (0x2A5442, 0x32644F, 0xDFB868)
            case .gold: return (0x6B2D3C, 0x7E3748, 0xE6BF72)
            case .aurora: return (0x34466B, 0x425782, 0x9BE0D0)
            case .candy: return (0x8E2D3D, 0xA63649, 0xF3E6D8)
            case .custom: return (0x2E4B5C, 0x395C70, ornament.customColor)
            }
        }()

        let boxMat = paperMaterial(boxRGB)
        let lidMat = paperMaterial(lidRGB)
        let ribbonMat = satinRibbonMaterial(ribbonRGB)

        let w: CGFloat = 1.44
        let h: CGFloat = 1.06
        let d: CGFloat = 1.44

        // Main box body
        let body = SCNBox(width: w, height: h, length: d, chamferRadius: 0.045)
        body.firstMaterial = boxMat
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, h / 2, 0)
        root.addChildNode(bodyNode)

        // Overhanging lid (casts real contact shadow onto box body)
        let lidH: CGFloat = 0.28
        let lid = SCNBox(width: w + 0.12, height: lidH, length: d + 0.12, chamferRadius: 0.042)
        lid.firstMaterial = lidMat
        let lidNode = SCNNode(geometry: lid)
        lidNode.position = SCNVector3(0, h - lidH * 0.28, 0)
        root.addChildNode(lidNode)

        // Crossed satin ribbon bands around body & lid
        let bandW: CGFloat = 0.24
        for rotated in [false, true] {
            let bodyBand = SCNBox(width: rotated ? w + 0.025 : bandW,
                                  height: h + 0.01,
                                  length: rotated ? bandW : d + 0.025,
                                  chamferRadius: 0.012)
            bodyBand.firstMaterial = ribbonMat
            let bn = SCNNode(geometry: bodyBand)
            bn.position = SCNVector3(0, h / 2, 0)
            root.addChildNode(bn)

            let lidBand = SCNBox(width: rotated ? w + 0.145 : bandW,
                                 height: lidH + 0.025,
                                 length: rotated ? bandW : d + 0.145,
                                 chamferRadius: 0.014)
            lidBand.firstMaterial = ribbonMat
            let ln = SCNNode(geometry: lidBand)
            ln.position = SCNVector3(0, h - lidH * 0.28, 0)
            root.addChildNode(ln)
        }

        // Sculpted 3D satin bow on top
        let bowTopY = h + lidH * 0.24
        let bowNode = SCNNode()
        bowNode.position = SCNVector3(0, bowTopY, 0)
        root.addChildNode(bowNode)

        let knot = SCNSphere(radius: 0.125)
        knot.firstMaterial = ribbonMat
        let knotNode = SCNNode(geometry: knot)
        knotNode.scale = SCNVector3(1.15, 0.85, 1.15)
        knotNode.position = SCNVector3(0, 0.07, 0)
        bowNode.addChildNode(knotNode)

        let loopAngles: [(yaw: CGFloat, tilt: CGFloat, scale: CGFloat)] = [
            (0.0, 0.42, 1.0), (.pi, 0.42, 1.0),
            (.pi / 2 + 0.25, 0.48, 0.86), (-.pi / 2 + 0.25, 0.48, 0.86)
        ]
        for spec in loopAngles {
            let loop = SCNTorus(ringRadius: 0.21 * spec.scale, pipeRadius: 0.068 * spec.scale)
            loop.ringSegmentCount = 36
            loop.pipeSegmentCount = 18
            loop.firstMaterial = ribbonMat
            let lNode = SCNNode(geometry: loop)
            lNode.scale = SCNVector3(1.25, 0.55, 0.92)
            let wrapper = SCNNode()
            wrapper.eulerAngles.y = spec.yaw
            lNode.position = SCNVector3(0.22 * spec.scale, 0.16 * spec.scale, 0)
            lNode.eulerAngles.z = spec.tilt
            wrapper.addChildNode(lNode)
            bowNode.addChildNode(wrapper)
        }

        return setupCamera(in: scene, position: SCNVector3(0, 1.58, 3.65), lookAt: SCNVector3(0, 0.66, 0), fov: 36)
    }

    // MARK: - Procedural Texture Generators

    private static func makeWinterEnvironmentMap(width: Int, height: Int) -> CGImage? {
        WinterArtwork.bitmap(width: width, height: height) { ink in
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            // Cobalt winter sky -> soft horizon -> deep slate ground
            ink.gradient(bounds, [0x152A44, 0x2A4D73, 0x527396, 0x1E2F45, 0x0C1624])
            // Cool moonlight softbox in upper-left
            ink.glow(CGFloat(width) * 0.28, CGFloat(height) * 0.25, CGFloat(height) * 0.42, 0xE6F4FF, alpha: 0.85)
            // Warm cabin window bounce in lower-right
            ink.glow(CGFloat(width) * 0.76, CGFloat(height) * 0.56, CGFloat(height) * 0.38, 0xFFC57A, alpha: 0.72)
        }
    }

    private static func makeNoiseNormalMap(size: Int, scale: CGFloat, strength: CGFloat, seed: UInt64) -> CGImage? {
        var rng = SnowRandom(state: seed)
        let grid = max(16, Int(CGFloat(size) / (4 * scale)))
        var heights = [CGFloat](repeating: 0, count: grid * grid)
        for i in heights.indices { heights[i] = rng.next() }
        // One blur pass for organic soft snow/felt micro-bumps
        var smooth = heights
        for y in 0..<grid {
            for x in 0..<grid {
                var sum: CGFloat = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = (x + dx + grid) % grid
                        let ny = (y + dy + grid) % grid
                        sum += heights[ny * grid + nx]
                    }
                }
                smooth[y * grid + x] = sum / 9
            }
        }
        return normalMapFromHeightfield(size: size, strength: strength) { u, v in
            let fx = u * CGFloat(grid)
            let fy = v * CGFloat(grid)
            let x0 = Int(fx) % grid
            let y0 = Int(fy) % grid
            let x1 = (x0 + 1) % grid
            let y1 = (y0 + 1) % grid
            let tx = fx - floor(fx)
            let ty = fy - floor(fy)
            let a = smooth[y0 * grid + x0] * (1 - tx) + smooth[y0 * grid + x1] * tx
            let b = smooth[y1 * grid + x0] * (1 - tx) + smooth[y1 * grid + x1] * tx
            return a * (1 - ty) + b * ty
        }
    }

    private static func makeKnitNormalMap(size: Int) -> CGImage? {
        normalMapFromHeightfield(size: size, strength: 2.2) { u, v in
            let rib = sin(u * .pi * 2 * 10) * 0.5
            let stitch = sin((v * 18 + abs(sin(u * .pi * 10)) * 0.45) * .pi * 2) * 0.5
            return 0.5 + 0.35 * rib + 0.25 * stitch
        }
    }

    private static func makeLinenNormalMap(size: Int) -> CGImage? {
        normalMapFromHeightfield(size: size, strength: 1.1) { u, v in
            0.5 + 0.25 * sin(u * .pi * 2 * 24) + 0.25 * sin(v * .pi * 2 * 24)
        }
    }

    private static func makeBrushedNormalMap(size: Int) -> CGImage? {
        var rng = SnowRandom(state: 777)
        let stripes = (0..<size).map { _ in rng.next() }
        return normalMapFromHeightfield(size: size, strength: 1.2) { _, v in
            let idx = min(size - 1, max(0, Int(v * CGFloat(size))))
            return stripes[idx]
        }
    }

    private static func normalMapFromHeightfield(size: Int, strength: CGFloat, sample: (CGFloat, CGFloat) -> CGFloat) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let step = 1.0 / CGFloat(size)
        for y in 0..<size {
            let v = CGFloat(y) * step
            for x in 0..<size {
                let u = CGFloat(x) * step
                let hL = sample((u - step + 1).truncatingRemainder(dividingBy: 1), v)
                let hR = sample((u + step).truncatingRemainder(dividingBy: 1), v)
                let hD = sample(u, (v - step + 1).truncatingRemainder(dividingBy: 1))
                let hU = sample(u, (v + step).truncatingRemainder(dividingBy: 1))
                let dx = (hL - hR) * strength
                let dy = (hD - hU) * strength
                let dz: CGFloat = 1.0
                let len = sqrt(dx * dx + dy * dy + dz * dz)
                let offset = (y * size + x) * 4
                pixels[offset + 0] = UInt8(min(255, max(0, ((dx / len) * 0.5 + 0.5) * 255)))
                pixels[offset + 1] = UInt8(min(255, max(0, ((dy / len) * 0.5 + 0.5) * 255)))
                pixels[offset + 2] = UInt8(min(255, max(0, ((dz / len) * 0.5 + 0.5) * 255)))
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
