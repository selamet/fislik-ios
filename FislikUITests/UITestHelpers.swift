import XCTest

extension XCUIApplication {
    /// Scrolls until `element` sits in the middle of the screen, away from the
    /// header and the home indicator, and waits for the scroll to settle.
    /// `isHittable` alone is not enough: an element half under the bottom
    /// edge counts as hittable but the tap lands on the system gesture area.
    func scrollToMiddle(_ element: XCUIElement, attempts: Int = 12) {
        for _ in 0..<attempts {
            let height = frame.height
            if element.exists {
                let f = element.frame
                if f.minY > height * 0.18 && f.maxY < height * 0.75 { break }
                if f.minY <= height * 0.18 { swipeDown(velocity: .slow) } else { swipeUp(velocity: .slow) }
            } else {
                swipeUp(velocity: .slow)
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        Thread.sleep(forTimeInterval: 1)
    }
}
