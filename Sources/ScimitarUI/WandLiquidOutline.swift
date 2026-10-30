import SwiftUI

/// A continuous, transparent outline: travel toward a neighbouring card
/// stretches its leading edge before the selected cell changes.
struct WandLiquidOutline: Shape {
    var pullX: Double
    var pullY: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(pullX, pullY) }
        set { pullX = newValue.first; pullY = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let x = min(1, max(-1, pullX)), y = min(1, max(-1, pullY))
        let horizontal = rect.width * 0.28
        let vertical = rect.height * 0.28
        let left = CGFloat(max(0, -x)) * horizontal, right = CGFloat(max(0, x)) * horizontal
        let top = CGFloat(max(0, -y)) * vertical, bottom = CGFloat(max(0, y)) * vertical
        let r = min(18, min(rect.width, rect.height) * 0.18)
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x:x0+r,y:y0))
        p.addCurve(to:CGPoint(x:x1-r,y:y0),control1:CGPoint(x:x0+rect.width*0.35,y:y0-top),control2:CGPoint(x:x0+rect.width*0.65,y:y0-top))
        p.addQuadCurve(to:CGPoint(x:x1,y:y0+r),control:CGPoint(x:x1,y:y0))
        p.addCurve(to:CGPoint(x:x1,y:y1-r),control1:CGPoint(x:x1+right,y:y0+rect.height*0.35),control2:CGPoint(x:x1+right,y:y0+rect.height*0.65))
        p.addQuadCurve(to:CGPoint(x:x1-r,y:y1),control:CGPoint(x:x1,y:y1))
        p.addCurve(to:CGPoint(x:x0+r,y:y1),control1:CGPoint(x:x0+rect.width*0.65,y:y1+bottom),control2:CGPoint(x:x0+rect.width*0.35,y:y1+bottom))
        p.addQuadCurve(to:CGPoint(x:x0,y:y1-r),control:CGPoint(x:x0,y:y1))
        p.addCurve(to:CGPoint(x:x0,y:y0+r),control1:CGPoint(x:x0-left,y:y0+rect.height*0.65),control2:CGPoint(x:x0-left,y:y0+rect.height*0.35))
        p.addQuadCurve(to:CGPoint(x:x0+r,y:y0),control:CGPoint(x:x0,y:y0))
        p.closeSubpath()
        return p
    }
}
