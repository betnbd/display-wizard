import AppKit

/// A monochrome companion to the app artwork, rendered at the screen's scale.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let monitor = NSBezierPath()
            monitor.lineWidth = 1.4
            monitor.lineCapStyle = .round
            monitor.lineJoinStyle = .round
            // Leave the upper-right bezel open around the sparkle.
            monitor.move(to: NSPoint(x: 14, y: 14.25))
            monitor.line(to: NSPoint(x: 3.25, y: 14.25))
            monitor.curve(to: NSPoint(x: 1.75, y: 12.75), controlPoint1: NSPoint(x: 2.25, y: 14.25), controlPoint2: NSPoint(x: 1.75, y: 13.75))
            monitor.line(to: NSPoint(x: 1.75, y: 5.75))
            monitor.curve(to: NSPoint(x: 3.25, y: 4.25), controlPoint1: NSPoint(x: 1.75, y: 4.75), controlPoint2: NSPoint(x: 2.25, y: 4.25))
            monitor.line(to: NSPoint(x: 17.25, y: 4.25))
            monitor.curve(to: NSPoint(x: 18.75, y: 5.75), controlPoint1: NSPoint(x: 18.25, y: 4.25), controlPoint2: NSPoint(x: 18.75, y: 4.75))
            monitor.line(to: NSPoint(x: 18.75, y: 9))
            monitor.stroke()

            let stand = NSBezierPath()
            stand.lineWidth = 1.4
            stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 10.25, y: 4.25))
            stand.line(to: NSPoint(x: 10.25, y: 1.75))
            stand.move(to: NSPoint(x: 7, y: 1.75))
            stand.line(to: NSPoint(x: 13.5, y: 1.75))
            stand.stroke()

            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: 18, y: 17))
            sparkle.line(to: NSPoint(x: 19.05, y: 14.05))
            sparkle.line(to: NSPoint(x: 22, y: 13))
            sparkle.line(to: NSPoint(x: 19.05, y: 11.95))
            sparkle.line(to: NSPoint(x: 18, y: 9))
            sparkle.line(to: NSPoint(x: 16.95, y: 11.95))
            sparkle.line(to: NSPoint(x: 14, y: 13))
            sparkle.line(to: NSPoint(x: 16.95, y: 14.05))
            sparkle.close()
            sparkle.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Display Wizard"
        return image
    }
}
