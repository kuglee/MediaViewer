import UIKit

extension UINavigationBar {
    func snapshotViewWithSafeArea(afterScreenUpdates: Bool) -> UIView? {
        guard let snapshot = snapshotView(afterScreenUpdates: afterScreenUpdates) else {
            return nil
        }

        snapshot.frame = frame

        let containerFrame: CGRect = .init(
            x: 0,
            y:0,
            width: frame.width,
            height: frame.maxY
        )
        let containerView = UIView(frame: containerFrame)
        containerView.addSubview(snapshot)
        containerView.backgroundColor = standardAppearance.backgroundColor
        containerView.layer.zPosition = .greatestFiniteMagnitude

        return containerView
    }
}
