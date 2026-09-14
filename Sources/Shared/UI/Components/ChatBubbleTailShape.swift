import SwiftUI

struct ChatBubbleTailShape: Shape {
    let isOutgoing: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailWidth: CGFloat = 8
        let tailHeight: CGFloat = 7
        var path = Path()
        if isOutgoing {
            // Top-left
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            // Top edge
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            // Top-right corner
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY))
            // Right edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            // Bottom-right corner
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY))
            // Bottom edge before tail
            path.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: rect.maxY))
            // Tail
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - 2, y: rect.maxY + tailHeight),
                control: CGPoint(x: rect.maxX - tailWidth, y: rect.maxY + 2))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 2),
                control: CGPoint(x: rect.maxX - 4, y: rect.maxY + 1))
            // Bottom-left
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY))
            // Left edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            // Top-left corner
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            // Incoming — mirror of outgoing
            // Top-right
            path.move(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            // Top edge
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            // Top-left corner
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + radius),
                control: CGPoint(x: rect.minX, y: rect.minY))
            // Left edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            // Bottom-left corner
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY))
            // Bottom edge before tail
            path.addLine(to: CGPoint(x: rect.minX + tailWidth, y: rect.maxY))
            // Tail
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + 2, y: rect.maxY + tailHeight),
                control: CGPoint(x: rect.minX + tailWidth, y: rect.maxY + 2))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + 6, y: rect.maxY - 2),
                control: CGPoint(x: rect.minX + 4, y: rect.maxY + 1))
            // Bottom-right
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                control: CGPoint(x: rect.maxX, y: rect.maxY))
            // Right edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
            // Top-right corner
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.minY),
                control: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}
