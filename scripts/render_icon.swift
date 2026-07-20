// Burrow 图标渲染器:SceneKit 离屏渲染 3D 行星,再合成 macOS squircle 图标底板。
// 用法:swiftc -O render_icon.swift -o render_icon && ./render_icon 输出路径.png
import AppKit
import SceneKit

// MARK: - 可复现随机数

struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + next() * (hi - lo) }
}

var rng = LCG(seed: 20260719)

// MARK: - 程序化纹理

func bitmapContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// 有机的「大陆」斑块路径
func blobPath(center: CGPoint, radius: Double, wobble: Double, points: Int = 12) -> CGPath {
    let path = CGMutablePath()
    var pts: [CGPoint] = []
    for i in 0..<points {
        let angle = Double(i) / Double(points) * .pi * 2
        let r = radius * (1 - wobble + rng.next() * wobble * 2)
        pts.append(CGPoint(x: center.x + Foundation.cos(angle) * r,
                           y: center.y + Foundation.sin(angle) * r * 0.72))
    }
    path.move(to: CGPoint(x: (pts[0].x + pts[points - 1].x) / 2,
                          y: (pts[0].y + pts[points - 1].y) / 2))
    for i in 0..<points {
        let curr = pts[i]
        let nxt = pts[(i + 1) % points]
        path.addQuadCurve(to: CGPoint(x: (curr.x + nxt.x) / 2, y: (curr.y + nxt.y) / 2),
                          control: curr)
    }
    path.closeSubpath()
    return path
}

/// 赤道圆柱投影的地表纹理:海洋渐变 + 大陆 + 鼹鼠洞
func makeSurfaceTexture(width: Int = 2048, height: Int = 1024) -> CGImage {
    let ctx = bitmapContext(width: width, height: height)
    let w = Double(width), h = Double(height)

    // 海洋:纵向渐变
    let ocean = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [
                            CGColor(red: 0.16, green: 0.42, blue: 0.85, alpha: 1),
                            CGColor(red: 0.13, green: 0.55, blue: 0.86, alpha: 1),
                            CGColor(red: 0.10, green: 0.62, blue: 0.72, alpha: 1),
                           ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(ocean, start: .zero, end: CGPoint(x: 0, y: h), options: [])

    // 大陆(水平三连画避免接缝)
    let greens: [CGColor] = [
        CGColor(red: 0.22, green: 0.80, blue: 0.58, alpha: 1),
        CGColor(red: 0.27, green: 0.85, blue: 0.55, alpha: 1),
        CGColor(red: 0.18, green: 0.72, blue: 0.52, alpha: 1),
    ]
    var continentCenters: [CGPoint] = []
    for i in 0..<13 {
        let cx = rng.range(0, w)
        let cy = rng.range(h * 0.18, h * 0.82)
        let radius = rng.range(70, 210)
        continentCenters.append(CGPoint(x: cx, y: cy))
        let color = greens[i % greens.count]
        for offset in [-w, 0, w] {
            let path = blobPath(center: CGPoint(x: cx + offset, y: cy),
                                radius: radius, wobble: 0.45)
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
            // 高地:内部小一号的亮斑
            ctx.addPath(blobPath(center: CGPoint(x: cx + offset + rng.range(-20, 20),
                                                 y: cy + rng.range(-14, 14)),
                                 radius: radius * 0.45, wobble: 0.5))
            ctx.setFillColor(CGColor(red: 0.42, green: 0.93, blue: 0.65, alpha: 0.5))
            ctx.fillPath()
        }
    }

    // 品牌记号:鼹鼠洞(深色洞口 + 土堆环)
    if let hole = continentCenters.first {
        for offset in [-w, 0, w] {
            let c = CGPoint(x: hole.x + offset, y: hole.y)
            ctx.setFillColor(CGColor(red: 0.30, green: 0.52, blue: 0.38, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - 46, y: c.y - 34, width: 92, height: 68))
            ctx.setFillColor(CGColor(red: 0.05, green: 0.12, blue: 0.20, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - 30, y: c.y - 21, width: 60, height: 42))
        }
    }

    return ctx.makeImage()!
}

/// 云层纹理:柔和白色团块,带透明度
func makeCloudTexture(width: Int = 2048, height: Int = 1024) -> CGImage {
    let ctx = bitmapContext(width: width, height: height)
    let w = Double(width), h = Double(height)
    for _ in 0..<26 {
        let cx = rng.range(0, w)
        let cy = rng.range(h * 0.1, h * 0.9)
        let rx = rng.range(90, 260)
        let alpha = rng.range(0.18, 0.5)
        for offset in [-w, 0, w] {
            let center = CGPoint(x: cx + offset, y: cy)
            let cloud = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   colors: [CGColor(gray: 1, alpha: alpha),
                                            CGColor(gray: 1, alpha: 0)] as CFArray,
                                   locations: [0, 1])!
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: 1, y: rng.range(0.3, 0.5))
            ctx.drawRadialGradient(cloud, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: rx, options: [])
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()!
}

// MARK: - 3D 场景

func buildScene() -> (SCNScene, SCNNode) {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear

    // 行星
    let sphere = SCNSphere(radius: 1.0)
    sphere.segmentCount = 120
    let surface = SCNMaterial()
    surface.lightingModel = .physicallyBased
    surface.diffuse.contents = makeSurfaceTexture()
    surface.roughness.contents = 0.42
    surface.metalness.contents = 0.0
    sphere.materials = [surface]
    let planet = SCNNode(geometry: sphere)
    planet.eulerAngles = SCNVector3(0.12, 2.2, 0)
    scene.rootNode.addChildNode(planet)

    // 云层(稍大的透明球)
    let cloudSphere = SCNSphere(radius: 1.018)
    cloudSphere.segmentCount = 120
    let clouds = SCNMaterial()
    clouds.lightingModel = .lambert
    clouds.diffuse.contents = makeCloudTexture()
    clouds.transparencyMode = .rgbZero // 黑色即透明?不——用 alpha
    clouds.transparencyMode = .default
    clouds.blendMode = .alpha
    clouds.writesToDepthBuffer = false
    cloudSphere.materials = [clouds]
    let cloudNode = SCNNode(geometry: cloudSphere)
    cloudNode.eulerAngles = SCNVector3(0.05, 0.8, 0)
    scene.rootNode.addChildNode(cloudNode)

    // 大气辉光:再大一圈、恒定发光的半透明壳,边缘可见
    let glowSphere = SCNSphere(radius: 1.06)
    glowSphere.segmentCount = 90
    let glow = SCNMaterial()
    glow.lightingModel = .constant
    glow.diffuse.contents = NSColor.clear
    glow.emission.contents = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 1)
    glow.transparency = 0.22
    glow.cullMode = .front // 只画背面壳,形成边缘光晕
    glow.writesToDepthBuffer = false
    glowSphere.materials = [glow]
    scene.rootNode.addChildNode(SCNNode(geometry: glowSphere))

    // 金色星环
    let torus = SCNTorus(ringRadius: 1.62, pipeRadius: 0.042)
    torus.ringSegmentCount = 200
    let gold = SCNMaterial()
    gold.lightingModel = .physicallyBased
    gold.diffuse.contents = NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.32, alpha: 1)
    gold.metalness.contents = 0.85
    gold.roughness.contents = 0.28
    gold.emission.contents = NSColor(calibratedRed: 0.45, green: 0.32, blue: 0.10, alpha: 1)
    torus.materials = [gold]
    let ring = SCNNode(geometry: torus)
    ring.eulerAngles = SCNVector3(-0.42, 0, 0.34)
    scene.rootNode.addChildNode(ring)

    // 灯光
    let key = SCNNode()
    key.light = SCNLight()
    key.light!.type = .directional
    key.light!.intensity = 1500
    key.light!.color = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.92, alpha: 1)
    key.eulerAngles = SCNVector3(-0.45, -0.75, 0)
    scene.rootNode.addChildNode(key)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light!.type = .directional
    fill.light!.intensity = 220
    fill.light!.color = NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1)
    fill.eulerAngles = SCNVector3(0.2, 0.9, 0)
    scene.rootNode.addChildNode(fill)

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light!.type = .ambient
    ambient.light!.intensity = 130
    ambient.light!.color = NSColor(calibratedRed: 0.5, green: 0.6, blue: 0.8, alpha: 1)
    scene.rootNode.addChildNode(ambient)

    // 相机(HDR + 泛光)
    let camera = SCNCamera()
    camera.fieldOfView = 42
    camera.wantsHDR = true
    camera.bloomThreshold = 0.55
    camera.bloomIntensity = 0.9
    camera.bloomBlurRadius = 18
    let camNode = SCNNode()
    camNode.camera = camera
    camNode.position = SCNVector3(0, 0.45, 4.6)
    camNode.look(at: SCNVector3(0, -0.02, 0))
    return (scene, camNode)
}

// MARK: - 合成

func renderIcon() -> NSImage {
    let (scene, camNode) = buildScene()
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camNode
    renderer.autoenablesDefaultLighting = false
    let planetShot = renderer.snapshot(atTime: 0,
                                       with: CGSize(width: 1800, height: 1800),
                                       antialiasingMode: .multisampling4X)

    let size = NSSize(width: 1024, height: 1024)
    let icon = NSImage(size: size)
    icon.lockFocus()
    defer { icon.unlockFocus() }
    guard let cg = NSGraphicsContext.current?.cgContext else { return icon }

    // squircle 底板:深空渐变
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    plate.addClip()
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.13, alpha: 1),
    ])!
    bg.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824), angle: -90)

    // 星星
    for _ in 0..<70 {
        let x = rng.range(120, 904)
        let y = rng.range(120, 904)
        let r = rng.range(1.2, 4.5)
        let bright = rng.next()
        cg.saveGState()
        if bright > 0.75 {
            cg.setShadow(offset: .zero, blur: 10,
                         color: CGColor(gray: 1, alpha: 0.9))
        }
        cg.setFillColor(CGColor(gray: 1, alpha: 0.25 + bright * 0.6))
        cg.fillEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
        cg.restoreGState()
    }

    // 行星(带投影)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -22), blur: 55,
                 color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    planetShot.draw(in: NSRect(x: 92, y: 76, width: 840, height: 840),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    cg.restoreGState()

    return icon
}

// MARK: - 入口

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon3D.png"
let icon = renderIcon()
guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("生成 PNG 失败\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("已生成 \(output)")
