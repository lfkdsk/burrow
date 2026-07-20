// Burrow 应用内行星图标渲染器:为五大模块各渲染一颗 3D 行星(透明背景 PNG)。
// 用法:swiftc -O render_planets.swift -o render_planets && ./render_planets 输出目录
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

var rng = LCG(seed: 5)

func bitmapContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

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

/// 陨石坑:暗色坑底 + 受光侧亮环
func drawCrater(_ ctx: CGContext, at c: CGPoint, radius r: Double, darkness: Double) {
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: darkness))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: darkness * 0.9))
    ctx.setLineWidth(r * 0.22)
    ctx.addArc(center: c, radius: r * 0.94, startAngle: .pi * 0.15, endAngle: .pi * 0.85,
               clockwise: false)
    ctx.strokePath()
}

// MARK: - 各行星纹理(2:1 赤道圆柱投影)

let W = 1024, H = 512
let dW = Double(W), dH = Double(H)

func earthTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    let ocean = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [
                            CGColor(red: 0.15, green: 0.44, blue: 0.87, alpha: 1),
                            CGColor(red: 0.12, green: 0.58, blue: 0.84, alpha: 1),
                            CGColor(red: 0.10, green: 0.66, blue: 0.68, alpha: 1),
                           ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(ocean, start: .zero, end: CGPoint(x: 0, y: dH), options: [])
    let greens: [CGColor] = [
        CGColor(red: 0.24, green: 0.80, blue: 0.55, alpha: 1),
        CGColor(red: 0.30, green: 0.86, blue: 0.52, alpha: 1),
        CGColor(red: 0.20, green: 0.72, blue: 0.50, alpha: 1),
    ]
    for i in 0..<12 {
        let cx = rng.range(0, dW), cy = rng.range(dH * 0.18, dH * 0.82)
        let radius = rng.range(45, 120)
        for offset in [-dW, 0, dW] {
            ctx.addPath(blobPath(center: CGPoint(x: cx + offset, y: cy),
                                 radius: radius, wobble: 0.45))
            ctx.setFillColor(greens[i % greens.count])
            ctx.fillPath()
            ctx.addPath(blobPath(center: CGPoint(x: cx + offset + rng.range(-12, 12),
                                                 y: cy + rng.range(-8, 8)),
                                 radius: radius * 0.45, wobble: 0.5))
            ctx.setFillColor(CGColor(red: 0.45, green: 0.94, blue: 0.62, alpha: 0.5))
            ctx.fillPath()
        }
    }
    // 极地冰盖
    ctx.setFillColor(CGColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 0.9))
    ctx.fill(CGRect(x: 0, y: dH - 26, width: dW, height: 26))
    ctx.fill(CGRect(x: 0, y: 0, width: dW, height: 20))
    return ctx.makeImage()!
}

func cloudTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    for _ in 0..<22 {
        let cx = rng.range(0, dW), cy = rng.range(dH * 0.1, dH * 0.9)
        let rx = rng.range(50, 150), alpha = rng.range(0.2, 0.5)
        for offset in [-dW, 0, dW] {
            let cloud = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   colors: [CGColor(gray: 1, alpha: alpha),
                                            CGColor(gray: 1, alpha: 0)] as CFArray,
                                   locations: [0, 1])!
            ctx.saveGState()
            ctx.translateBy(x: cx + offset, y: cy)
            ctx.scaleBy(x: 1, y: rng.range(0.3, 0.5))
            ctx.drawRadialGradient(cloud, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: rx, options: [])
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()!
}

func marsTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [
                            CGColor(red: 0.79, green: 0.42, blue: 0.24, alpha: 1),
                            CGColor(red: 0.88, green: 0.52, blue: 0.30, alpha: 1),
                            CGColor(red: 0.70, green: 0.32, blue: 0.18, alpha: 1),
                          ] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: dH), options: [])
    // 暗色玄武岩地(火星「海」)
    for _ in 0..<15 {
        let cx = rng.range(0, dW), cy = rng.range(dH * 0.2, dH * 0.8)
        let radius = rng.range(40, 130)
        for offset in [-dW, 0, dW] {
            ctx.addPath(blobPath(center: CGPoint(x: cx + offset, y: cy),
                                 radius: radius, wobble: 0.55))
            ctx.setFillColor(CGColor(red: 0.42, green: 0.19, blue: 0.11, alpha: 0.38))
            ctx.fillPath()
        }
    }
    // 沙尘亮纹
    for _ in 0..<18 {
        let cx = rng.range(0, dW), cy = rng.range(0, dH)
        let w = rng.range(60, 200), h = rng.range(5, 14)
        for offset in [-dW, 0, dW] {
            ctx.setFillColor(CGColor(red: 0.98, green: 0.72, blue: 0.45, alpha: 0.16))
            ctx.fillEllipse(in: CGRect(x: cx + offset - w / 2, y: cy - h / 2, width: w, height: h))
        }
    }
    // 陨石坑
    for _ in 0..<22 {
        drawCrater(ctx, at: CGPoint(x: rng.range(0, dW), y: rng.range(dH * 0.15, dH * 0.85)),
                   radius: rng.range(5, 18), darkness: 0.22)
    }
    // 极冠
    ctx.setFillColor(CGColor(red: 0.97, green: 0.94, blue: 0.90, alpha: 0.95))
    ctx.fill(CGRect(x: 0, y: dH - 34, width: dW, height: 34))
    ctx.setFillColor(CGColor(red: 0.97, green: 0.94, blue: 0.90, alpha: 0.7))
    ctx.fill(CGRect(x: 0, y: 0, width: dW, height: 16))
    return ctx.makeImage()!
}

func mercuryTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [
                            CGColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1),
                            CGColor(red: 0.58, green: 0.60, blue: 0.66, alpha: 1),
                            CGColor(red: 0.44, green: 0.46, blue: 0.52, alpha: 1),
                          ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: dH), options: [])
    // 大盆地
    for _ in 0..<8 {
        let cx = rng.range(0, dW), cy = rng.range(dH * 0.2, dH * 0.8)
        let radius = rng.range(50, 110)
        for offset in [-dW, 0, dW] {
            ctx.addPath(blobPath(center: CGPoint(x: cx + offset, y: cy),
                                 radius: radius, wobble: 0.4))
            ctx.setFillColor(CGColor(gray: 0.30, alpha: 0.25))
            ctx.fillPath()
        }
    }
    // 密集陨石坑
    for _ in 0..<70 {
        drawCrater(ctx, at: CGPoint(x: rng.range(0, dW), y: rng.range(dH * 0.08, dH * 0.92)),
                   radius: rng.range(4, 26), darkness: 0.3)
    }
    return ctx.makeImage()!
}

func jupiterTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    let palette: [CGColor] = [
        CGColor(red: 0.93, green: 0.86, blue: 0.72, alpha: 1), // 奶油
        CGColor(red: 0.85, green: 0.64, blue: 0.42, alpha: 1), // 茶棕
        CGColor(red: 0.76, green: 0.46, blue: 0.28, alpha: 1), // 锈红
        CGColor(red: 0.96, green: 0.91, blue: 0.80, alpha: 1), // 亮带
        CGColor(red: 0.81, green: 0.55, blue: 0.35, alpha: 1), // 橙棕
    ]
    ctx.setFillColor(palette[0])
    ctx.fill(CGRect(x: 0, y: 0, width: dW, height: dH))
    // 从上往下逐条覆盖:每条带的上边缘为整数周期的波浪(保证左右接缝闭合)
    var y = 0.0
    var i = 0
    while y < dH {
        let bandHeight = rng.range(34, 72)
        let color = palette[(i + 1) % palette.count]
        let amp = rng.range(3, 9)
        let freq = Double(Int(rng.range(2, 5)))
        let phase = rng.range(0, .pi * 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: y + Foundation.sin(phase) * amp))
        var x = 0.0
        while x <= dW {
            path.addLine(to: CGPoint(x: x,
                                     y: y + Foundation.sin(x / dW * .pi * 2 * freq + phase) * amp))
            x += 16
        }
        path.addLine(to: CGPoint(x: dW, y: dH))
        path.addLine(to: CGPoint(x: 0, y: dH))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        y += bandHeight
        i += 1
    }
    // 湍流细纹
    for _ in 0..<40 {
        let cx = rng.range(0, dW), cy = rng.range(0, dH)
        let w = rng.range(40, 160), h = rng.range(3, 8)
        let bright = rng.next() > 0.5
        for offset in [-dW, 0, dW] {
            ctx.setFillColor(bright ? CGColor(gray: 1, alpha: 0.14)
                                    : CGColor(red: 0.4, green: 0.22, blue: 0.1, alpha: 0.14))
            ctx.fillEllipse(in: CGRect(x: cx + offset - w / 2, y: cy - h / 2, width: w, height: h))
        }
    }
    // 大红斑(纹理 y 向下为南半球,放在下三分之一)
    let spot = CGPoint(x: dW * 0.68, y: dH * 0.34)
    ctx.setFillColor(CGColor(red: 0.96, green: 0.90, blue: 0.78, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: spot.x - 82, y: spot.y - 40, width: 164, height: 80))
    ctx.setFillColor(CGColor(red: 0.80, green: 0.36, blue: 0.22, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: spot.x - 68, y: spot.y - 32, width: 136, height: 64))
    ctx.setFillColor(CGColor(red: 0.90, green: 0.48, blue: 0.30, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: spot.x - 46, y: spot.y - 21, width: 92, height: 42))
    ctx.setFillColor(CGColor(red: 0.97, green: 0.62, blue: 0.42, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: spot.x - 22, y: spot.y - 10, width: 44, height: 20))
    return ctx.makeImage()!
}

func sunTexture() -> CGImage {
    let ctx = bitmapContext(width: W, height: H)
    let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [
                            CGColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 1),
                            CGColor(red: 0.98, green: 0.62, blue: 0.12, alpha: 1),
                            CGColor(red: 0.90, green: 0.44, blue: 0.06, alpha: 1),
                          ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: dH), options: [])
    // 米粒组织:细碎明暗斑
    for _ in 0..<380 {
        let c = CGPoint(x: rng.range(0, dW), y: rng.range(0, dH))
        let r = rng.range(3, 12)
        let bright = rng.next() > 0.45
        ctx.setFillColor(bright ? CGColor(red: 1.0, green: 0.92, blue: 0.50, alpha: 0.35)
                                : CGColor(red: 0.72, green: 0.30, blue: 0.04, alpha: 0.30))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6))
    }
    // 耀斑亮区
    for _ in 0..<8 {
        let c = CGPoint(x: rng.range(0, dW), y: rng.range(dH * 0.2, dH * 0.8))
        let r = rng.range(30, 70)
        let flare = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                               colors: [CGColor(red: 1, green: 0.95, blue: 0.60, alpha: 0.7),
                                        CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawRadialGradient(flare, startCenter: c, startRadius: 0, endCenter: c, endRadius: r,
                               options: [])
    }
    // 少量太阳黑子
    for _ in 0..<4 {
        let c = CGPoint(x: rng.range(0, dW), y: rng.range(dH * 0.3, dH * 0.7))
        let r = rng.range(6, 14)
        ctx.setFillColor(CGColor(red: 0.55, green: 0.25, blue: 0.05, alpha: 0.7))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
    }
    return ctx.makeImage()!
}

// MARK: - 渲染

struct PlanetSpec {
    let name: String
    let texture: () -> CGImage
    var roughness: Double = 0.55
    var metalness: Double = 0.0
    var emissive = false          // 太阳:自发光
    var clouds = false            // 地球:云层
    var euler = SCNVector3(0.1, 0, 0)
    var glow: (NSColor, Double, Double)? // (颜色, 壳半径, 透明度)
    var cameraZ = 3.03
    var bloom = 0.7
}

let specs: [PlanetSpec] = [
    PlanetSpec(name: "earth", texture: earthTexture, roughness: 0.42, clouds: true,
               euler: SCNVector3(0.12, 2.2, 0),
               glow: (NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 1), 1.06, 0.22)),
    PlanetSpec(name: "mars", texture: marsTexture, roughness: 0.68,
               euler: SCNVector3(0.15, 1.0, 0),
               glow: (NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.3, alpha: 1), 1.05, 0.10)),
    PlanetSpec(name: "mercury", texture: mercuryTexture, roughness: 0.78, metalness: 0.08,
               euler: SCNVector3(0.1, 2.6, 0)),
    PlanetSpec(name: "jupiter", texture: jupiterTexture, roughness: 0.5,
               euler: SCNVector3(0.08, 5.2, 0.06),
               glow: (NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.5, alpha: 1), 1.05, 0.08)),
    PlanetSpec(name: "sun", texture: sunTexture, emissive: true,
               euler: SCNVector3(0, 0.8, 0),
               glow: (NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.20, alpha: 1), 1.15, 0.5),
               cameraZ: 3.83, bloom: 0.9),
]

func render(_ spec: PlanetSpec) -> NSImage {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear

    let sphere = SCNSphere(radius: 1.0)
    sphere.segmentCount = 120
    let mat = SCNMaterial()
    if spec.emissive {
        // 太阳:lambert + 相机正面光,产生「临边昏暗」的球体感;低强度自发光保留辉光
        mat.lightingModel = .lambert
        let tex = spec.texture()
        mat.diffuse.contents = tex
        mat.emission.contents = tex
        mat.emission.intensity = 0.35
    } else {
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = spec.texture()
        mat.roughness.contents = spec.roughness
        mat.metalness.contents = spec.metalness
    }
    sphere.materials = [mat]
    let planet = SCNNode(geometry: sphere)
    planet.eulerAngles = spec.euler
    scene.rootNode.addChildNode(planet)

    if spec.clouds {
        let cloudSphere = SCNSphere(radius: 1.018)
        cloudSphere.segmentCount = 120
        let cm = SCNMaterial()
        cm.lightingModel = .lambert
        cm.diffuse.contents = cloudTexture()
        cm.blendMode = .alpha
        cm.writesToDepthBuffer = false
        cloudSphere.materials = [cm]
        scene.rootNode.addChildNode(SCNNode(geometry: cloudSphere))
    }

    if let (color, radius, alpha) = spec.glow {
        let shell = SCNSphere(radius: radius)
        shell.segmentCount = 90
        let gm = SCNMaterial()
        gm.lightingModel = .constant
        gm.diffuse.contents = NSColor.clear
        gm.emission.contents = color
        gm.transparency = alpha
        gm.cullMode = .front
        gm.writesToDepthBuffer = false
        shell.materials = [gm]
        scene.rootNode.addChildNode(SCNNode(geometry: shell))
        if spec.emissive { // 太阳:再加一层更大更淡的日冕
            let outer = SCNSphere(radius: radius * 1.3)
            outer.segmentCount = 90
            let om = SCNMaterial()
            om.lightingModel = .constant
            om.diffuse.contents = NSColor.clear
            om.emission.contents = color
            om.transparency = alpha * 0.35
            om.cullMode = .front
            om.writesToDepthBuffer = false
            outer.materials = [om]
            scene.rootNode.addChildNode(SCNNode(geometry: outer))
        }
    }

    if spec.emissive {
        // 相机正面光:让太阳边缘自然变暗
        let front = SCNNode()
        front.light = SCNLight()
        front.light!.type = .directional
        front.light!.intensity = 1100
        front.light!.color = NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.7, alpha: 1)
        front.eulerAngles = SCNVector3(0, 0, 0) // 沿 -z 照向行星,与相机同向
        scene.rootNode.addChildNode(front)
    } else {
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
        fill.light!.intensity = 230
        fill.light!.color = NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1)
        fill.eulerAngles = SCNVector3(0.2, 0.9, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 150
        ambient.light!.color = NSColor(calibratedRed: 0.5, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    let camera = SCNCamera()
    camera.fieldOfView = 42
    camera.wantsHDR = true
    camera.bloomThreshold = 0.55
    camera.bloomIntensity = spec.bloom
    camera.bloomBlurRadius = 16
    let camNode = SCNNode()
    camNode.camera = camera
    camNode.position = SCNVector3(0, 0, spec.cameraZ)
    scene.rootNode.addChildNode(camNode)

    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camNode
    renderer.autoenablesDefaultLighting = false
    return renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512),
                             antialiasingMode: .multisampling4X)
}

// MARK: - 入口

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 调试:--jupiter-sweep 渲染 4 个自转角度以定位大红斑
if CommandLine.arguments.contains("--jupiter-sweep") {
    for (idx, yAngle) in [0.0, 1.57, 3.14, 4.71].enumerated() {
        var spec = specs[3]
        spec.euler = SCNVector3(0.08, yAngle, 0.06)
        let image = render(spec)
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(outDir)/jupiter_sweep\(idx).png"))
        }
    }
    print("sweep 完成")
    exit(0)
}

for spec in specs {
    let image = render(spec)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("\(spec.name) 生成失败\n", stderr)
        exit(1)
    }
    let path = "\(outDir)/\(spec.name).png"
    try png.write(to: URL(fileURLWithPath: path))
    print("已生成 \(path)")
}
