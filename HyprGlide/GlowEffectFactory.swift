//
//  GlowEffectFactory.swift
//  HyprGlide
//
//  Utility factory for building reusable neon glow nodes.
//

import SpriteKit
import CoreImage

enum GlowEffectFactory {
    /// Builds a circular neon glow using an effect node with gaussian blur.
    /// - Parameters:
    ///   - radius: Base radius of the circle before any scaling.
    ///   - color: Color of the glow core.
    ///   - blurRadius: Blur radius applied by the gaussian filter.
    ///   - alpha: Alpha applied to the glow shape before blurring.
    ///   - scale: Optional scale to enlarge the glow relative to the base radius.
    static func makeCircularGlow(radius: CGFloat,
                                 color: SKColor,
                                 blurRadius: CGFloat,
                                 alpha: CGFloat = 0.85,
                                 scale: CGFloat = 1.7) -> SKEffectNode {
        let glowShape = SKShapeNode(circleOfRadius: radius)
        glowShape.fillColor = color
        glowShape.strokeColor = .clear
        glowShape.lineWidth = 0
        glowShape.alpha = alpha
        glowShape.isAntialiased = true
        glowShape.blendMode = .add
        glowShape.setScale(scale)
        
        return makeEffectNode(with: glowShape, blurRadius: blurRadius)
    }
    
    /// Builds a rounded rectangle neon glow using an effect node with gaussian blur.
    /// - Parameters:
    ///   - size: Base size of the rectangle before scaling.
    ///   - cornerRadius: Corner radius for the rounded rectangle.
    ///   - color: Color of the glow core.
    ///   - blurRadius: Blur radius applied by the gaussian filter.
    ///   - alpha: Alpha applied to the glow shape before blurring.
    ///   - scale: Optional scale to enlarge the glow relative to the base size.
    static func makeRoundedRectangleGlow(size: CGSize,
                                         cornerRadius: CGFloat,
                                         color: SKColor,
                                         blurRadius: CGFloat,
                                         alpha: CGFloat = 0.8,
                                         scale: CGFloat = 1.4) -> SKEffectNode {
        let glowShape = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        glowShape.fillColor = color
        glowShape.strokeColor = .clear
        glowShape.lineWidth = 0
        glowShape.alpha = alpha
        glowShape.isAntialiased = true
        glowShape.blendMode = .add
        glowShape.xScale = scale
        glowShape.yScale = scale
        
        return makeEffectNode(with: glowShape, blurRadius: blurRadius)
    }
    
    /// Builds a triangle neon glow using an effect node with gaussian blur.
    /// - Parameters:
    ///   - sideLength: Length of each side of the equilateral triangle.
    ///   - color: Color of the glow core.
    ///   - blurRadius: Blur radius applied by the gaussian filter.
    ///   - alpha: Alpha applied to the glow shape before blurring.
    ///   - scale: Optional scale to enlarge the glow relative to the base size.
    static func makeTriangleGlow(sideLength: CGFloat,
                                 color: SKColor,
                                 blurRadius: CGFloat,
                                 alpha: CGFloat = 0.85,
                                 scale: CGFloat = 1.35) -> SKEffectNode {
        let path = trianglePath(sideLength: sideLength)
        let glowShape = SKShapeNode(path: path)
        glowShape.fillColor = color
        glowShape.strokeColor = .clear
        glowShape.lineWidth = 0
        glowShape.alpha = alpha
        glowShape.isAntialiased = true
        glowShape.blendMode = .add
        glowShape.setScale(scale)
        
        return makeEffectNode(with: glowShape, blurRadius: blurRadius)
    }
    
    /// Creates a CGPath for an equilateral triangle centered at origin.
    static func trianglePath(sideLength: CGFloat) -> CGPath {
        let height = sideLength * sqrt(3) / 2
        let path = CGMutablePath()
        // Top vertex
        path.move(to: CGPoint(x: 0, y: height * 2 / 3))
        // Bottom-right vertex
        path.addLine(to: CGPoint(x: sideLength / 2, y: -height / 3))
        // Bottom-left vertex
        path.addLine(to: CGPoint(x: -sideLength / 2, y: -height / 3))
        path.closeSubpath()
        return path
    }
    
    /// Private helper that wraps the supplied shape in an effect node.
    private static func makeEffectNode(with shape: SKShapeNode,
                                       blurRadius: CGFloat) -> SKEffectNode {
        let effectNode = SKEffectNode()
        effectNode.shouldRasterize = true
        effectNode.shouldEnableEffects = true
        effectNode.addChild(shape)
        
        if let filter = CIFilter(name: "CIGaussianBlur") {
            filter.setValue(blurRadius, forKey: kCIInputRadiusKey)
            effectNode.filter = filter
        }
        
        return effectNode
    }
}


